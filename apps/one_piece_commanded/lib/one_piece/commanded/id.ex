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

  @doc """
  Transform the UUID into the default format.

  Useful when to transform a uuid with `:hex` format into a uuid with `:default` format.

      iex> OnePiece.Commanded.Id.to_default_format("f81d4fae7dec11d0a76500a0c91e6bf6")
      "f81d4fae-7dec-11d0-a765-00a0c91e6bf6"
  """
  @spec to_default_format(uuid :: String.t()) :: String.t()
  def to_default_format(uuid) do
    Uniq.UUID.to_string(uuid, :default)
  end
end
