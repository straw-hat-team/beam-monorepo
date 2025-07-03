defmodule Trogon.Error.MetadataValue do
  @moduledoc """
  Represents a metadata entry with both value and visibility level.

  Each metadata entry in a Trogon error contains not just the value,
  but also its visibility level which determines who can see this metadata.

  ## Visibility Levels

  - `:INTERNAL` - Only visible to internal systems and developers (default)
  - `:PRIVATE` - Visible to authenticated users but not public
  - `:PUBLIC` - Visible to everyone including end users

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret data", :PRIVATE)
      %Trogon.Error.MetadataValue{value: "secret data", visibility: :PRIVATE}

      iex> Trogon.Error.MetadataValue.new(123)
      %Trogon.Error.MetadataValue{value: "123", visibility: :INTERNAL}

  """

  @enforce_keys [:value, :visibility]
  defstruct [:value, :visibility]

  @type visibility :: :INTERNAL | :PRIVATE | :PUBLIC

  @type t :: %__MODULE__{
          value: String.t(),
          visibility: visibility()
        }

  @doc """
  Creates a new MetadataValue with the given value and visibility.

  The value will be converted to a string if it's not already one.

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret", :PRIVATE)
      %Trogon.Error.MetadataValue{value: "secret", visibility: :PRIVATE}

      iex> Trogon.Error.MetadataValue.new(123, :PUBLIC)
      %Trogon.Error.MetadataValue{value: "123", visibility: :PUBLIC}
  """
  @spec new(term(), visibility()) :: t()
  def new(value, visibility) when visibility in [:INTERNAL, :PRIVATE, :PUBLIC] do
    %__MODULE__{value: to_string(value), visibility: visibility}
  end

  @doc """
  Creates a new MetadataValue with the given value and default visibility.

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret")
      %Trogon.Error.MetadataValue{value: "secret", visibility: :INTERNAL}
  """
  @spec new(term()) :: t()
  def new(value) do
    new(value, :INTERNAL)
  end
end
