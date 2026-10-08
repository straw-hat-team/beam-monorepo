defmodule Trogon.Outbox.Position do
  @moduledoc """
  Where an event sits in its source: the source and its seq.
  """

  alias Trogon.Outbox.{MessageId, Seq, Source}

  @enforce_keys [:source, :seq]
  defstruct [:source, :seq]

  @type t :: %__MODULE__{source: Source.t(), seq: Seq.t()}

  @spec new(Source.t(), Seq.t()) :: t()
  def new(%Source{} = source, %Seq{} = seq), do: %__MODULE__{source: source, seq: seq}

  @spec message_id(t()) :: MessageId.t()
  def message_id(%__MODULE__{} = position), do: MessageId.new(position)
end
