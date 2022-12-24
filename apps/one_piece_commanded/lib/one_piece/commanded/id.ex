defmodule OnePiece.Commanded.Id do
  @moduledoc """
  A module for dealing IDs.
  """

  @doc """
  Generates a new ID.
  """
  @callback new() :: String.t()

  @doc """
  Generates a UUID using the version 4 scheme, as described in
  [RFC 4122](https://datatracker.ietf.org/doc/html/rfc4122).

      iex> OnePiece.Commanded.Id.new() |> String.length()
      36
  """
  @spec new :: String.t()
  def new do
    Uniq.UUID.uuid4()
  end
end
