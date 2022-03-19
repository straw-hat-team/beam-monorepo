defmodule OnePiece.Result.ExpectedError do
  @moduledoc """
  Error raised when trying to `OnePiece.Result.expect_ok!/2` or `OnePiece.Result.expect_err!/2`.
  """

  @type t :: %__MODULE__{}

  defexception [:message, :value]

  @doc """
  Convert exception to string.
  """
  @spec message(error :: t) :: String.t()
  def message(e), do: e.message
end
