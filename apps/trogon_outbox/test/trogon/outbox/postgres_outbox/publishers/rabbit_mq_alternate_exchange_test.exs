defmodule Trogon.Outbox.PostgresOutbox.Publishers.RabbitMQAlternateExchangeTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Publishers.RabbitMQ
  alias Trogon.Outbox.Publishers.RabbitMQ.Connection
  alias Trogon.Outbox.TestSupport.RabbitMQSupport

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

    capture_queue = RabbitMQSupport.declare_queue!(setup_channel)
    ae_exchange = "outbox_rmq_ae_#{System.unique_integer([:positive])}"
    exchange = "outbox_rmq_primary_#{System.unique_integer([:positive])}"

    :ok = AMQP.Exchange.declare(setup_channel, ae_exchange, :fanout, durable: true)
    :ok = AMQP.Queue.bind(setup_channel, capture_queue, ae_exchange)

    on_exit(fn ->
      with {:ok, conn} <- AMQP.Connection.open(@rabbitmq_url),
           {:ok, chan} <- AMQP.Channel.open(conn) do
        AMQP.Exchange.delete(chan, exchange)
        AMQP.Exchange.delete(chan, ae_exchange)
        AMQP.Connection.close(conn)
      end
    end)

    on_exit(fn -> if Process.alive?(setup_connection.pid), do: AMQP.Connection.close(setup_connection) end)

    holder = start_supervised!({Connection, url: @rabbitmq_url, retry_interval: 100})
    wait_until(fn -> match?({:ok, _}, Connection.get(holder)) end)

    {:ok, connection: holder, capture_queue: capture_queue, ae_exchange: ae_exchange, exchange: exchange}
  end

  defp cursor_tuple(event), do: {event.cursor.xid, event.cursor.id}

  test "a message no binding on the primary exchange can route is captured by the alternate exchange, not blocked",
       %{
         prefix: prefix,
         connection: connection,
         capture_queue: capture_queue,
         ae_exchange: ae_exchange,
         exchange: exchange
       } do
    start_relay!(prefix,
      publisher:
        {RabbitMQ,
         connection: connection,
         exchange: exchange,
         alternate_exchange: ae_exchange,
         routing_key: fn _partition -> "no.such.binding" end}
    )

    [appended] = append!(prefix, "source-a", "caught-by-ae")

    wait_until(fn -> cursor_row(prefix, "test", 0) == cursor_tuple(appended) end)

    [{payload, _meta}] = RabbitMQSupport.consume(capture_queue, 1)
    assert payload == "caught-by-ae"
  end

  test "the same unroutable message blocks the relay when no alternate exchange is configured", %{
    prefix: prefix,
    connection: connection
  } do
    start_relay!(prefix,
      restart: :temporary,
      publisher: {RabbitMQ, connection: connection, routing_key: fn _partition -> "no.such.queue" end}
    )

    append!(prefix, "source-a", "stuck")
    Process.sleep(500)

    assert cursor_row(prefix, "test", 0) == {0, 0}
  end

  test "an alternate exchange on the default exchange is refused as a config error", %{connection: connection} do
    batch = batch_of("x")

    assert_raise ArgumentError, ~r/default exchange/, fn ->
      RabbitMQ.publish(batch, connection: connection, alternate_exchange: "whatever")
    end
  end

  defp batch_of(payload) do
    event = %Trogon.Outbox.Event{
      position: Trogon.Outbox.Position.new(Trogon.Outbox.Source.new!("source-a"), Trogon.Outbox.Seq.first()),
      partition: Trogon.Outbox.Partition.new!(0),
      cursor: Trogon.Outbox.Cursor.new(1, 1),
      payload: payload,
      inserted_at: DateTime.utc_now()
    }

    Trogon.Outbox.Batch.new("test", event.partition, [event])
  end
end
