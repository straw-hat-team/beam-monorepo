defmodule Trogon.Outbox.Event do
  @moduledoc """
  An appended outbox event.

  `cursor` carries the ordering `xid`, which is the writing transaction id raised to at least the
  ordering `xid` of the previous event of the same source, so `(xid, id)` order never disagrees
  with seq order within a source.
  """

  alias Trogon.Outbox.{Cursor, MessageId, Partition, Position}

  @enforce_keys [:position, :partition, :cursor, :payload, :inserted_at]
  defstruct [:position, :partition, :cursor, :payload, :inserted_at]

  @type t :: %__MODULE__{
          position: Position.t(),
          partition: Partition.t(),
          cursor: Cursor.t(),
          payload: binary(),
          inserted_at: DateTime.t()
        }

  @spec message_id(t()) :: MessageId.t()
  def message_id(%__MODULE__{position: position}), do: Position.message_id(position)
end
