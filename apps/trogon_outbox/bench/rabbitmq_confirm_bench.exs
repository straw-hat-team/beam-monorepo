# Compares batching publisher confirms, as Trogon.Outbox.Publishers.RabbitMQ does per outbox
# batch, against confirming every message before publishing the next one.
#
#     TROGON_OUTBOX_RABBITMQ_URL=amqp://guest:guest@localhost:5672 mix run bench/rabbitmq_confirm_bench.exs
#
# TROGON_OUTBOX_BENCH_MESSAGES sets how many messages each run publishes, 20000 by default.
# TROGON_OUTBOX_BENCH_PAYLOAD_SIZE sets the payload size in bytes, 200 by default.

defmodule Trogon.Outbox.Bench.RabbitMQConfirm do
  @queue "outbox_rmq_confirm_bench"

  def run do
    url = System.fetch_env!("TROGON_OUTBOX_RABBITMQ_URL")
    messages = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_MESSAGES", "20000"))
    payload = :binary.copy("x", String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_PAYLOAD_SIZE", "200")))

    {:ok, connection} = AMQP.Connection.open(url)
    {:ok, setup_channel} = AMQP.Channel.open(connection)
    {:ok, _} = AMQP.Queue.declare(setup_channel, @queue, durable: true)

    IO.puts("#{messages} messages, #{byte_size(payload)} byte payload\n")
    IO.puts("| confirms | batch size | messages/s | elapsed ms |")
    IO.puts("| --- | --- | --- | --- |")

    for batch_size <- [1, 100, 500, 1_000] do
      AMQP.Queue.purge(setup_channel, @queue)
      {:ok, channel} = AMQP.Channel.open(connection)
      :ok = AMQP.Confirm.select(channel)

      {elapsed_us, :ok} = :timer.tc(fn -> publish_in_batches(channel, payload, messages, batch_size) end)
      elapsed_ms = elapsed_us / 1_000

      AMQP.Channel.close(channel)
      report("batch", batch_size, messages, elapsed_ms)
    end

    AMQP.Queue.purge(setup_channel, @queue)
    {:ok, channel} = AMQP.Channel.open(connection)
    :ok = AMQP.Confirm.select(channel)

    {elapsed_us, :ok} = :timer.tc(fn -> publish_per_message(channel, payload, messages) end)
    report("per message", 1, messages, elapsed_us / 1_000)

    AMQP.Channel.close(channel)
    AMQP.Queue.delete(setup_channel, @queue)
    AMQP.Connection.close(connection)
  end

  defp publish_in_batches(_channel, _payload, 0, _batch_size), do: :ok

  defp publish_in_batches(channel, payload, remaining, batch_size) do
    this_batch = min(batch_size, remaining)

    for _ <- 1..this_batch do
      AMQP.Basic.publish(channel, "", @queue, payload, mandatory: true, persistent: true)
    end

    true = AMQP.Confirm.wait_for_confirms(channel, 30_000)
    publish_in_batches(channel, payload, remaining - this_batch, batch_size)
  end

  defp publish_per_message(_channel, _payload, 0), do: :ok

  defp publish_per_message(channel, payload, remaining) do
    AMQP.Basic.publish(channel, "", @queue, payload, mandatory: true, persistent: true)
    true = AMQP.Confirm.wait_for_confirms(channel, 30_000)
    publish_per_message(channel, payload, remaining - 1)
  end

  defp report(mode, batch_size, messages, elapsed_ms) do
    throughput = round(messages / (elapsed_ms / 1_000))
    IO.puts("| #{mode} | #{batch_size} | #{throughput} | #{Float.round(elapsed_ms, 1)} |")
  end
end

Trogon.Outbox.Bench.RabbitMQConfirm.run()
