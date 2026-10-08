defmodule Trogon.Outbox.TestSupport.RabbitMQSupport do
  @moduledoc """
  Helpers for tests that publish to a real RabbitMQ broker through
  `Trogon.Outbox.Publishers.RabbitMQ`.

  Every test using these helpers is skipped unless `TROGON_OUTBOX_RABBITMQ_URL` is set, the same
  way the PgBouncer tests are skipped without `TROGON_OUTBOX_PGBOUNCER_URL`.
  """

  alias Trogon.Outbox.Publishers.RabbitMQ.Connection

  @spec url() :: String.t() | nil
  def url, do: System.get_env("TROGON_OUTBOX_RABBITMQ_URL")

  @doc "Declares a fresh durable queue, deleted on test exit, and returns its name."
  def declare_queue!(channel) do
    queue = "outbox_rmq_#{System.unique_integer([:positive])}"
    {:ok, _} = AMQP.Queue.declare(channel, queue, durable: true)

    ExUnit.Callbacks.on_exit(fn ->
      with {:ok, conn} <- AMQP.Connection.open(url()),
           {:ok, chan} <- AMQP.Channel.open(conn) do
        AMQP.Queue.delete(chan, queue)
        AMQP.Connection.close(conn)
      end
    end)

    queue
  end

  @doc "Starts a connection and a setup channel against the test broker."
  def open!(retry_interval \\ 200) do
    {:ok, connection} = AMQP.Connection.open(url())
    {:ok, channel} = AMQP.Channel.open(connection)
    holder = ExUnit.Callbacks.start_supervised!({Connection, url: url(), retry_interval: retry_interval})
    %{connection: connection, channel: channel, holder: holder}
  end

  @doc "Consumes `count` messages from `queue` with manual ack, in delivery order."
  def consume(queue, count, timeout \\ 10_000) do
    {:ok, connection} = AMQP.Connection.open(url())
    {:ok, channel} = AMQP.Channel.open(connection)
    {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

    messages = collect(channel, count, deadline(timeout), [])
    AMQP.Connection.close(connection)
    messages
  end

  @doc "The current message count of `queue`."
  def message_count(channel, queue) do
    {:ok, %{message_count: count}} = AMQP.Queue.declare(channel, queue, durable: true)
    count
  end

  defp collect(_channel, count, _deadline, acc) when length(acc) >= count, do: Enum.reverse(acc)

  defp collect(channel, count, deadline, acc) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:basic_deliver, payload, meta} ->
        AMQP.Basic.ack(channel, meta.delivery_tag)
        collect(channel, count, deadline, [{payload, meta} | acc])
    after
      remaining -> ExUnit.Assertions.flunk("expected #{count} messages, got #{length(acc)}")
    end
  end

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout
end
