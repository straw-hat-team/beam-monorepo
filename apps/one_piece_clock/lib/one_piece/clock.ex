defmodule OnePiece.Clock do
  @moduledoc """
  Defines a Clock Behavior to deal with time dependency.
  """

  @doc """
  Returns the current UTC date time.
  """
  @callback utc_now() :: DateTime.t()
end
