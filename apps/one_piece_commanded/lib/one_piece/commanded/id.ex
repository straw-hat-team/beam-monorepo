defmodule OnePiece.Commanded.Id do
  @moduledoc """
  A module for dealing IDs.
  """

  @doc """
  Generates a UUID using the version 4 scheme, as described in [RFC 4122](https://datatracker.ietf.org/doc/html/rfc4122),
  with a hex format.
  """
  @spec new :: String.t()
  def new do
    Uniq.UUID.uuid4(:hex)
  end
end
