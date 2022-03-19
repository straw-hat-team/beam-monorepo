defmodule OnePiece.Result.OkUnwrapError do
  @moduledoc """
  Error raised when trying to unwrap an `t:OnePiece.Result.ok/0` result.
  """

  @type t :: %__MODULE__{}

  defexception [:reason]

  @doc """
  Convert exception to string.
  """
  @spec message(error :: t) :: String.t()
  def message(e) do
    "expected an Ok result but #{inspect(e.reason)} was given"
  end
end
