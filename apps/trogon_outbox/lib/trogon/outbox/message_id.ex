defmodule Trogon.Outbox.MessageId do
  @moduledoc """
  A stable message id derived from the source and seq, the same on every replay of an event, so
  consumers can deduplicate. Its string form is `source:seq`, which parses unambiguously from the
  right even when the source contains a colon.
  """

  alias Trogon.Outbox.{Position, Seq, Source}

  @enforce_keys [:position]
  defstruct [:position]

  @type t :: %__MODULE__{position: Position.t()}

  @spec new(Position.t()) :: t()
  def new(%Position{} = position), do: %__MODULE__{position: position}

  @spec parse(String.t()) :: {:ok, t()} | {:error, :invalid_message_id}
  def parse(value) when is_binary(value) do
    with [seq, source] <- value |> String.reverse() |> String.split(":", parts: 2),
         {seq, ""} <- seq |> String.reverse() |> Integer.parse(),
         {:ok, seq} <- Seq.new(seq),
         {:ok, source} <- source |> String.reverse() |> Source.new() do
      {:ok, new(Position.new(source, seq))}
    else
      _invalid -> {:error, :invalid_message_id}
    end
  end

  defimpl String.Chars do
    def to_string(%{position: %{source: source, seq: seq}}), do: "#{source}:#{seq}"
  end
end
