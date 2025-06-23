defmodule Trogon.Result.ExpectedError do
  @moduledoc """
  Error raised when trying to `Trogon.Result.expect_ok!/2` or `Trogon.Result.expect_err!/2`.
  """

  @type t :: %__MODULE__{}

  defexception [:message, :value]

  @doc """
  Convert exception to string.
  """
  @spec message(error :: t) :: String.t()
  def message(e), do: e.message
end
