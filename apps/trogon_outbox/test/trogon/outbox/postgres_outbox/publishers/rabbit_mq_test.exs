defmodule Trogon.Outbox.PostgresOutbox.Publishers.RabbitMQTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Event
  alias Trogon.Outbox.Publishers.RabbitMQ
  alias Trogon.Outbox.Publishers.RabbitMQ.Connection
  alias Trogon.Outbox.TestSupport.{RabbitMQSupport, TcpProxy}

  @rabbitmq_url RabbitMQSupport.url()

  if is_nil(@rabbitmq_url) do
    @moduletag skip: "set TROGON_OUTBOX_RABBITMQ_URL to a RabbitMQ broker"
  end

  # Falls back to "" so the type checker never sees the nilable value below: this module is
  # skipped at runtime whenever it would matter, so the fallback itself is never dialed.
  @rabbitmq_url @rabbitmq_url || ""

  @moduletag partitions: 1

  setup do
    {:ok, setup_connection} = AMQP.Connection.open(@rabbitmq_url)
    {:ok, setup_channel} = AMQP.Channel.open(setup_connection)
    queue = RabbitMQSupport.declare_queue!(setup_channel)
    on_exit(fn -> if Process.alive?(setup_connection.pid), do: AMQP.Connection.close(setup_connection) end)

    holder = start_supervised!({Connection, url: @rabbitmq_url, retry_interval: 100})
    wait_until(fn -> match?({:ok, _}, Connection.get(holder)) end)

    {:ok, connection: holder, queue: queue}
  end

  defp publisher(connection, queue), do: {RabbitMQ, connection: connection, routing_key: fn _partition -> queue end}

  defp cursor_tuple(event), do: {event.cursor.xid, event.cursor.id}

  defp connected?(connection) do
    match?({:ok, _}, Connection.get(connection, 15_000))
  catch
    :exit, _ -> false
  end

  defp disconnected?(connection) do
    match?({:error, :disconnected}, Connection.get(connection, 15_000))
  catch
    :exit, _ -> false
  end

  test "a mandatory message with no routable queue does not advance the cursor", %{
    prefix: prefix,
    connection: connection
  } do
    start_relay!(prefix,
      restart: :temporary,
      publisher: {RabbitMQ, connection: connection, routing_key: fn _partition -> "no.such.queue" end}
    )

    append!(prefix, "source-a", "unroutable")
    Process.sleep(500)

    assert cursor_row(prefix, "test", 0) == {0, 0}
  end

  test "a broker restart does not advance the cursor and the batch is redelivered once reconnected",
       %{prefix: prefix, queue: queue} do
    uri = URI.parse(@rabbitmq_url)
    proxy = start_supervised!({TcpProxy, host: uri.host, port: uri.port || 5672})
    proxied_url = %{uri | host: "127.0.0.1", port: TcpProxy.port(proxy)} |> URI.to_string()

    connection = start_supervised!({Connection, url: proxied_url, retry_interval: 100}, id: :severed_connection)
    wait_until(fn -> connected?(connection) end)

    :ok = TcpProxy.sever(proxy)
    wait_until(fn -> disconnected?(connection) end, 20_000)

    appended = append!(prefix, "source-a", ["one", "two"])
    start_relay!(prefix, publisher: publisher(connection, queue))

    wait_until(fn -> cursor_row(prefix, "test", 0) != nil end, 5_000)
    assert cursor_row(prefix, "test", 0) == {0, 0}

    :ok = TcpProxy.restore(proxy)
    wait_until(fn -> connected?(connection) end, 30_000)

    delivered = RabbitMQSupport.consume(queue, 2, 30_000)
    assert Enum.map(delivered, fn {payload, _meta} -> payload end) == Enum.map(appended, & &1.payload)

    wait_until(fn -> cursor_row(prefix, "test", 0) == cursor_tuple(List.last(appended)) end, 20_000)
  end

  test "ordering per source holds across a relay restart", %{prefix: prefix, connection: connection, queue: queue} do
    relay = start_relay!(prefix, restart: :temporary, publisher: publisher(connection, queue))

    before_restart = append!(prefix, "source-a", ["one", "two"])
    wait_until(fn -> cursor_row(prefix, "test", 0) == cursor_tuple(List.last(before_restart)) end)

    ref = Process.monitor(relay)
    Process.exit(relay, :kill)
    assert_receive {:DOWN, ^ref, :process, _pid, :killed}, 5_000

    after_restart = append!(prefix, "source-a", ["three", "four"])
    start_relay!(prefix, publisher: publisher(connection, queue))

    wait_until(fn -> cursor_row(prefix, "test", 0) == cursor_tuple(List.last(after_restart)) end, 10_000)

    delivered = RabbitMQSupport.consume(queue, 4)

    assert Enum.map(delivered, fn {payload, _meta} -> payload end) ==
             Enum.map(before_restart ++ after_restart, & &1.payload)
  end

  test "duplicates on redelivery carry the same message_id", %{prefix: prefix, connection: connection, queue: queue} do
    test_pid = self()
    appended = append!(prefix, "source-a", "once")
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    start_relay!(prefix,
      restart: :temporary,
      handler: fn batch ->
        attempt = Agent.get_and_update(attempts, &{&1, &1 + 1})
        result = RabbitMQ.publish(batch, connection: connection, routing_key: fn _partition -> queue end)
        send(test_pid, {:attempt, attempt, result})
        if attempt == 0, do: {:error, :forced_retry}, else: result
      end
    )

    assert_receive {:attempt, 0, :ok}, 10_000
    assert_receive {:attempt, 1, :ok}, 10_000

    wait_until(fn -> cursor_row(prefix, "test", 0) == cursor_tuple(List.last(appended)) end)

    [{_payload1, meta1}, {_payload2, meta2}] = RabbitMQSupport.consume(queue, 2)
    assert meta1.message_id == meta2.message_id
    assert meta1.message_id == to_string(Event.message_id(hd(appended)))
  end
end
