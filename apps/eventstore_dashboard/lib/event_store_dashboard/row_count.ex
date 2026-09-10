defmodule EventStoreDashboard.RowCount do
  @moduledoc false

  @enforce_keys [:value, :exact?]
  defstruct [:value, :exact?]

  @type t :: %__MODULE__{value: non_neg_integer(), exact?: boolean()}

  def zero, do: %__MODULE__{value: 0, exact?: true}

  def exact(value) when is_integer(value) and value >= 0 do
    %__MODULE__{value: value, exact?: true}
  end

  def estimated(value) when is_integer(value) and value > 0 do
    %__MODULE__{value: value, exact?: false}
  end

  def total_pages(%__MODULE__{value: 0}, _limit), do: 0

  def total_pages(%__MODULE__{value: value}, limit) when is_integer(limit) and limit > 0 do
    div(value - 1, limit) + 1
  end

  defimpl String.Chars do
    def to_string(%{value: value, exact?: true}), do: Integer.to_string(value)
    def to_string(%{value: value, exact?: false}), do: "~" <> Integer.to_string(value)
  end
end
