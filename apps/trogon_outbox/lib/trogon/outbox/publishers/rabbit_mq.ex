defmodule Trogon.Outbox.Publishers.RabbitMQ do
  @moduledoc """
  Publishes a batch to RabbitMQ with publisher confirms, persistent delivery, and the mandatory
  flag, one queue per partition so order inside RabbitMQ matches the batch's commit order.

  A channel is opened and closed per batch, on the connection `:connection` currently holds. A
  batch is published only once every message in it is both confirmed and routed: any message
  returned as unroutable, any nack, and any connection error all leave the batch unpublished, so
  the relay retries it. `Trogon.Outbox.Event.message_id/1` is the same on every retry, so a
  consumer deduplicates a replayed batch on it. Every event in the batch is published before the
  channel waits for confirms once, so the broker round trip is paid per batch, not per event.

  A failure is classified before it is returned, and either way emits
  `[:trogon, :outbox, :publish, :failure]` with `:classification` in its metadata, `:temporary`
  for a failure a retry alone can fix (a nack, a confirm timeout, or the connection being down) or
  `:environmental` for one that needs an operator, such as a message no exchange could route. The
  relay retries either one with the same backoff and never skips ahead on its own; the
  classification is only a signal for alerting, never a reason to treat one failure differently
  from the other in the relay's own flow.

  ## Options

    * `:connection` - a `Trogon.Outbox.Publishers.RabbitMQ.Connection` server, or anything that
      answers `get/1` the same way. Required.
    * `:exchange` - the exchange to publish through, `""` (the default exchange, which routes
      directly to the queue named by `:routing_key`) by default.
    * `:exchange_type` - the type to declare `:exchange` as when `:alternate_exchange` is set,
      `:direct` by default. Unused without `:alternate_exchange`.
    * `:alternate_exchange` - an exchange to catch a message `:exchange` cannot route, declared as
      `:exchange`'s `alternate-exchange` argument before every publish. Bind it to a queue to keep
      what it catches instead of losing it. The broker tries it before concluding a mandatory
      message is unroutable, so nothing is lost as long as something is bound to it. Not
      compatible with the default exchange, which cannot be declared. `nil` by default, which
      keeps every unroutable message blocking the batch as a mandatory return.
    * `:routing_key` - a function from `Trogon.Outbox.Partition.t()` to a routing key,
      `&"outbox.partition.\#{&1.value}"` by default. AMQP 0-9-1 limits a routing key to 255 bytes;
      validate every partition's key with `validate_routing_keys!/2` once, when the relay starts.
    * `:max_payload_size` - the largest payload, in bytes, this publisher accepts,
      `Trogon.Outbox.Publisher.Limits.rabbitmq_default_max_message_size/0` (RabbitMQ 4's broker
      default `max_message_size`, 16 MiB) by default. `limits/1` builds a
      `Trogon.Outbox.Publisher.Limits.t()` from it for `Trogon.Outbox.append/4` to validate
      against before a payload this publisher would refuse ever commits.
    * `:confirm_timeout` - how long to wait for the broker to confirm the batch, in milliseconds,
      30000 by default. Passed to `AMQP.Confirm.wait_for_confirms/2` as `{confirm_timeout,
      :millisecond}`, since a bare integer there means seconds, not milliseconds.
    * `:return_grace_period` - how long to wait, after every event in the batch is confirmed, for
      a mandatory return that proves one of them was unroutable, in milliseconds, 50 by default.
      A return for a given delivery tag is not guaranteed to reach the channel before its
      confirm, so this is not optional.
  """

  @behaviour Trogon.Outbox.Publisher

  alias Trogon.Outbox.{Batch, Event, Partition}
  alias Trogon.Outbox.Publisher.Limits
  alias Trogon.Outbox.Publishers.RabbitMQ.Connection

  @max_routing_key_size 255

  @impl Trogon.Outbox.Publisher
  def publish(%Batch{} = batch, opts) do
    connection_server = Keyword.fetch!(opts, :connection)
    exchange = Keyword.get(opts, :exchange, "")
    exchange_type = Keyword.get(opts, :exchange_type, :direct)
    alternate_exchange = Keyword.get(opts, :alternate_exchange)
    routing_key_fun = Keyword.get(opts, :routing_key, &default_routing_key/1)
    confirm_timeout = Keyword.get(opts, :confirm_timeout, 30_000)
    return_grace_period = Keyword.get(opts, :return_grace_period, 50)
    limits = limits(opts)
    validate_exchange_config!(exchange, alternate_exchange)

    with :ok <- validate_batch(batch, limits),
         {:ok, connection} <- Connection.get(connection_server),
         {:ok, channel} <- AMQP.Channel.open(connection),
         :ok <- declare_alternate_exchange(channel, exchange, exchange_type, alternate_exchange) do
      try do
        publish_batch(channel, batch, exchange, routing_key_fun.(batch.partition), confirm_timeout, return_grace_period)
      after
        close(channel)
      end
    end
    |> classify_and_report(batch)
  end

  @impl Trogon.Outbox.Publisher
  def limits(opts), do: Limits.new!(Keyword.get(opts, :max_payload_size, Limits.rabbitmq_default_max_message_size()))

  @doc """
  Raises unless every partition's routing key fits AMQP 0-9-1's 255-byte routing key limit.

  Call this once, when the relay starts, with every partition it will ever hold and the same
  `:routing_key` and `:exchange` this publisher is configured with: a routing key depends only on
  the partition and the configured function, never on an event, so checking every partition once
  covers every event the relay will ever read.
  """
  @spec validate_routing_keys!([Partition.t()], keyword()) :: :ok
  def validate_routing_keys!(partitions, opts) do
    routing_key_fun = Keyword.get(opts, :routing_key, &default_routing_key/1)

    Enum.each(partitions, fn partition ->
      routing_key = routing_key_fun.(partition)
      size = byte_size(routing_key)

      if size > @max_routing_key_size do
        raise ArgumentError,
              "the routing key for partition #{partition} is #{size} bytes, over AMQP's #{@max_routing_key_size} " <>
                "byte limit: #{inspect(routing_key)}"
      end
    end)
  end

  defp validate_batch(batch, limits) do
    batch.events
    |> Enum.find_value(:ok, fn event ->
      case Limits.validate_payload(limits, event.payload) do
        :ok -> nil
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp validate_exchange_config!("", alternate_exchange) when is_binary(alternate_exchange) do
    raise ArgumentError, "the default exchange cannot declare an :alternate_exchange, set :exchange to a named one"
  end

  defp validate_exchange_config!(_exchange, _alternate_exchange), do: :ok

  defp declare_alternate_exchange(_channel, _exchange, _type, nil), do: :ok

  defp declare_alternate_exchange(channel, exchange, type, alternate_exchange) do
    AMQP.Exchange.declare(channel, exchange, type,
      durable: true,
      arguments: [{"alternate-exchange", :longstr, alternate_exchange}]
    )
  end

  defp publish_batch(channel, batch, exchange, routing_key, confirm_timeout, return_grace_period) do
    :ok = AMQP.Confirm.select(channel)
    :ok = AMQP.Basic.return(channel, self())

    Enum.each(batch.events, &publish_event(channel, exchange, routing_key, &1))

    case AMQP.Confirm.wait_for_confirms(channel, {confirm_timeout, :millisecond}) do
      true -> check_returns(return_grace_period)
      false -> {:error, :nacked}
      :timeout -> {:error, :confirm_timeout}
    end
  end

  defp publish_event(channel, exchange, routing_key, event) do
    AMQP.Basic.publish(channel, exchange, routing_key, event.payload,
      mandatory: true,
      persistent: true,
      message_id: to_string(Event.message_id(event))
    )
  end

  defp check_returns(return_grace_period) do
    receive do
      {:basic_return, _payload, _meta} ->
        drain_returns()
        {:error, :unroutable}
    after
      return_grace_period -> :ok
    end
  end

  defp drain_returns do
    receive do
      {:basic_return, _payload, _meta} -> drain_returns()
    after
      0 -> :ok
    end
  end

  defp close(channel) do
    if Process.alive?(channel.pid), do: AMQP.Channel.close(channel)
  catch
    :exit, _reason -> :ok
  end

  defp default_routing_key(partition), do: "outbox.partition.#{partition.value}"

  defp classify_and_report(:ok, _batch), do: :ok

  defp classify_and_report({:error, reason} = error, batch) do
    classification = classify(reason)

    :telemetry.execute(
      [:trogon, :outbox, :publish, :failure],
      %{batch_size: Batch.size(batch)},
      %{
        partition: batch.partition,
        sources: batch.events |> Enum.map(& &1.position.source) |> Enum.uniq(),
        message_ids: Enum.map(batch.events, &Event.message_id/1),
        reason: reason,
        classification: classification
      }
    )

    error
  end

  defp classify(:nacked), do: :temporary
  defp classify(:confirm_timeout), do: :temporary
  defp classify(:disconnected), do: :temporary
  defp classify(_other), do: :environmental
end
