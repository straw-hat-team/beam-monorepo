defmodule OnePiece.Error do
  @moduledoc """
  Defines a Error Behavior to deal with time dependency.
  """

  @doc """
  Returns the current UTC date time.
  """
  @callback utc_now() :: DateTime.t()
end
