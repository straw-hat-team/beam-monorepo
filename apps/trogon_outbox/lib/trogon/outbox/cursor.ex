defmodule Trogon.Outbox.Cursor do
  @moduledoc """
  How far a relay has published a partition: the ordering `xid` and `id` of the last event it
  published. Events are read strictly after the cursor in `(xid, id)` order.
  """

  @enforce_keys [:xid, :id]
  defstruct [:xid, :id]

  @type t :: %__MODULE__{xid: non_neg_integer(), id: non_neg_integer()}

  @spec start() :: t()
  def start, do: %__MODULE__{xid: 0, id: 0}

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(xid, id) when is_integer(xid) and xid >= 0 and is_integer(id) and id >= 0,
    do: %__MODULE__{xid: xid, id: id}

  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    cond do
      {left.xid, left.id} < {right.xid, right.id} -> :lt
      {left.xid, left.id} > {right.xid, right.id} -> :gt
      true -> :eq
    end
  end
end
