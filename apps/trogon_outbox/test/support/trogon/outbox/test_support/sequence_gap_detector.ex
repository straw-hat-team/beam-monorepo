defmodule Trogon.Outbox.TestSupport.SequenceGapDetector do
  @moduledoc false

  @doc """
  Given the per-source sequence numbers a consumer has seen, returns the
  numbers that are missing between the lowest and the highest one received.
  """
  @spec missing(list(pos_integer())) :: list(pos_integer())
  def missing([]), do: []

  def missing(sequence_numbers) do
    sorted = Enum.sort(sequence_numbers)
    Enum.to_list(List.first(sorted)..List.last(sorted)) -- sorted
  end
end
