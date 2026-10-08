defmodule Trogon.Outbox.PostgresOutbox.Publishers.RabbitMQTelemetryTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Batch, Event}
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
    queue = RabbitMQSupport.declare_queue!(setup_channel)
    on_exit(fn -> if Process.alive?(setup_connection.pid), do: AMQP.Connection.close(setup_connection) end)

    holder = start_supervised!({Connection, url: @rabbitmq_url, retry_interval: 100})
    wait_until(fn -> match?({:ok, _}, Connection.get(holder)) end)

    {:ok, connection: holder, channel: setup_channel, queue: queue}
  end

  defp attach(test) do
    test_pid = self()
    handler_id = {__MODULE__, test.test, make_ref()}

    :telemetry.attach(
      handler_id,
      [:trogon, :outbox, :publish, :failure],
      fn _event, measurements, metadata, _config -> send(test_pid, {:telemetry, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "an unroutable message is reported as an environmental failure, kept blocking",
       %{
         prefix: prefix,
         connection: connection
       } = test do
    attach(test)

    [event] = append!(prefix, "source-a", "unroutable")
    batch = Batch.new("test", event.partition, [event])

    assert {:error, :unroutable} =
             RabbitMQ.publish(batch, connection: connection, routing_key: fn _partition -> "no.such.queue" end)

    assert_receive {:telemetry, %{batch_size: 1}, metadata}, 5_000
    assert metadata.reason == :unroutable
    assert metadata.classification == :environmental
    assert metadata.partition == event.partition
    assert metadata.sources == [event.position.source]
    assert metadata.message_ids == [Event.message_id(event)]
  end

  test "a payload over max_payload_size is reported as an environmental failure, never published",
       %{
         prefix: prefix,
         connection: connection,
         channel: channel,
         queue: queue
       } = test do
    attach(test)

    [event] = append!(prefix, "source-a", :binary.copy("x", 20))
    batch = Batch.new("test", event.partition, [event])

    assert {:error, {:payload_too_large, 20, 10}} =
             RabbitMQ.publish(batch,
               connection: connection,
               routing_key: fn _partition -> queue end,
               max_payload_size: 10
             )

    assert_receive {:telemetry, _measurements, metadata}, 5_000
    assert metadata.reason == {:payload_too_large, 20, 10}
    assert metadata.classification == :environmental
    assert RabbitMQSupport.message_count(channel, queue) == 0
  end

  test "a confirm timeout is reported as a temporary failure",
       %{prefix: prefix, connection: connection, queue: queue} =
         test do
    attach(test)

    [event] = append!(prefix, "source-a", "slow")
    batch = Batch.new("test", event.partition, [event])

    assert {:error, :confirm_timeout} =
             RabbitMQ.publish(batch,
               connection: connection,
               routing_key: fn _partition -> queue end,
               confirm_timeout: 0
             )

    assert_receive {:telemetry, _measurements, metadata}, 5_000
    assert metadata.reason == :confirm_timeout
    assert metadata.classification == :temporary
  end
end
