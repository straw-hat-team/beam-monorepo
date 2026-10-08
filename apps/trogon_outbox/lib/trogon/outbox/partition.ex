defmodule Trogon.Outbox.Partition do
  @moduledoc """
  One of the fixed outbox partitions. A source always maps to the same partition, chosen by the
  database as `hash(source) mod N`, and exactly one relay consumes a partition at a time.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: non_neg_integer()}

  @spec new(non_neg_integer()) :: {:ok, t()} | {:error, :invalid_partition}
  def new(value) when is_integer(value) and value >= 0, do: {:ok, %__MODULE__{value: value}}
  def new(_value), do: {:error, :invalid_partition}

  @spec new!(non_neg_integer()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, partition} ->
        partition

      {:error, :invalid_partition} ->
        raise ArgumentError, "a partition must be a non-negative integer, got: #{inspect(value)}"
    end
  end

  @spec all(pos_integer()) :: [t()]
  def all(count) when is_integer(count) and count > 0, do: Enum.map(0..(count - 1), &new!/1)

  defimpl String.Chars do
    def to_string(%{value: value}), do: Integer.to_string(value)
  end
end
