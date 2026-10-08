defmodule Trogon.Outbox.Seq do
  @moduledoc """
  The gapless position of an event within its source, starting at 1 and following commit order.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: pos_integer()}

  @spec new(pos_integer()) :: {:ok, t()} | {:error, :invalid_seq}
  def new(value) when is_integer(value) and value > 0, do: {:ok, %__MODULE__{value: value}}
  def new(_value), do: {:error, :invalid_seq}

  @spec new!(pos_integer()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, seq} -> seq
      {:error, :invalid_seq} -> raise ArgumentError, "a seq must be a positive integer, got: #{inspect(value)}"
    end
  end

  @spec first() :: t()
  def first, do: %__MODULE__{value: 1}

  @spec next(t()) :: t()
  def next(%__MODULE__{value: value}), do: %__MODULE__{value: value + 1}

  defimpl String.Chars do
    def to_string(%{value: value}), do: Integer.to_string(value)
  end
end
