defmodule Trogon.Result.ErrUnwrapError do
  @moduledoc """
  Error raised when trying to unwrap an `t:Trogon.Result.err/0` result.
  """

  @type t :: %__MODULE__{}

  defexception [:value]

  @doc """
  Convert exception to string.
  """
  @spec message(error :: t) :: String.t()
  def message(e) do
    "expected an Err result but #{inspect(e.value)} was given"
  end
end
