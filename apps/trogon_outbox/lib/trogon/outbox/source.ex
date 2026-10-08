defmodule Trogon.Outbox.Source do
  @moduledoc """
  The stream an event belongs to, such as an aggregate or tenant id. Events of one source keep
  commit order.
  """

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: String.t()}

  @spec new(String.t()) :: {:ok, t()} | {:error, :invalid_source}
  def new(value) when is_binary(value) and byte_size(value) > 0, do: {:ok, %__MODULE__{value: value}}
  def new(_value), do: {:error, :invalid_source}

  @spec new!(String.t()) :: t()
  def new!(value) do
    case new(value) do
      {:ok, source} -> source
      {:error, :invalid_source} -> raise ArgumentError, "a source must be a non-empty string, got: #{inspect(value)}"
    end
  end

  defimpl String.Chars do
    def to_string(%{value: value}), do: value
  end
end
