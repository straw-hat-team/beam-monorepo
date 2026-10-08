defmodule Trogon.Outbox.Batch do
  @moduledoc """
  Events of one partition handed to a publisher at once, in `(xid, id)` order, which keeps each
  source in seq order. The relay advances its cursor past the batch only after the publisher
  returns `:ok` for all of it.
  """

  alias Trogon.Outbox.{Cursor, Event, Partition}

  @enforce_keys [:relay, :partition, :events]
  defstruct [:relay, :partition, :events]

  @type t :: %__MODULE__{relay: String.t(), partition: Partition.t(), events: [Event.t(), ...]}

  @spec new(String.t(), Partition.t(), [Event.t(), ...]) :: t()
  def new(relay, %Partition{} = partition, [_ | _] = events) when is_binary(relay),
    do: %__MODULE__{relay: relay, partition: partition, events: events}

  @spec cursor(t()) :: Cursor.t()
  def cursor(%__MODULE__{events: events}), do: List.last(events).cursor

  @spec size(t()) :: pos_integer()
  def size(%__MODULE__{events: events}), do: length(events)
end
