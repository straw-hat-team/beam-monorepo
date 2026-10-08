defmodule Trogon.Outbox.Publisher.Limits do
  @moduledoc """
  The limits a publisher enforces on an event, so an event the publisher could never deliver is
  never committed in the first place.

  `Trogon.Outbox.append/4` validates every payload against a `Limits.t()` before it writes
  anything, inside the business transaction, so an oversized payload raises instead of landing in
  the events table where only an environmental problem, never a bad event, is allowed to stall a
  partition. A publisher exposes the same limits through the optional
  `c:Trogon.Outbox.Publisher.limits/1` callback, built from the same options it publishes with, so
  `append/4` and the publisher agree on one `max_payload_size`.
  """

  @enforce_keys [:max_payload_size]
  defstruct [:max_payload_size]

  @type t :: %__MODULE__{max_payload_size: pos_integer()}

  @doc "RabbitMQ 4's broker default `max_message_size`, 16 MiB, documented at https://www.rabbitmq.com/docs/configure#config-items."
  @spec rabbitmq_default_max_message_size() :: pos_integer()
  def rabbitmq_default_max_message_size, do: 16 * 1024 * 1024

  @spec new(pos_integer()) :: {:ok, t()} | {:error, :invalid_max_payload_size}
  def new(max_payload_size) when is_integer(max_payload_size) and max_payload_size > 0,
    do: {:ok, %__MODULE__{max_payload_size: max_payload_size}}

  def new(_max_payload_size), do: {:error, :invalid_max_payload_size}

  @spec new!(pos_integer()) :: t()
  def new!(max_payload_size) do
    case new(max_payload_size) do
      {:ok, limits} ->
        limits

      {:error, :invalid_max_payload_size} ->
        raise ArgumentError, "max_payload_size must be a positive integer, got: #{inspect(max_payload_size)}"
    end
  end

  @doc "The limits a publisher enforces when nothing overrides `:max_payload_size`."
  @spec default() :: t()
  def default, do: new!(rabbitmq_default_max_message_size())

  @doc "Checks a payload against `:max_payload_size`."
  @spec validate_payload(t(), binary()) :: :ok | {:error, {:payload_too_large, pos_integer(), pos_integer()}}
  def validate_payload(%__MODULE__{max_payload_size: max}, payload) when is_binary(payload) do
    size = byte_size(payload)
    if size <= max, do: :ok, else: {:error, {:payload_too_large, size, max}}
  end

  @doc """
  Raises unless the broker accepts a message at least as large as `:max_payload_size`.

  Call this once, at relay or publisher start, against the broker's own `max_message_size`, not
  per event: the broker's limit does not change per message, so checking it once covers every
  event the limits ever validate.
  """
  @spec check_broker_max_message_size!(t(), pos_integer()) :: :ok
  def check_broker_max_message_size!(%__MODULE__{max_payload_size: max}, broker_max_message_size)
      when is_integer(broker_max_message_size) and broker_max_message_size > 0 do
    if broker_max_message_size >= max do
      :ok
    else
      raise ArgumentError,
            "the broker's max_message_size (#{broker_max_message_size} bytes) is smaller than the configured " <>
              "max_payload_size (#{max} bytes); lower max_payload_size or raise the broker's max_message_size"
    end
  end
end
