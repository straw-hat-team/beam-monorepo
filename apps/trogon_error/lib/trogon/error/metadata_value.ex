defmodule Trogon.Error.MetadataValue do
  @moduledoc """
  Represents a metadata entry with both value and visibility level.

  Each metadata entry in a Trogon error contains not just the value,
  but also its visibility level which determines who can see this metadata.

  ## Visibility Levels

  - `:internal` - Only visible to internal systems and developers (default)
  - `:private` - Visible to authenticated users but not public
  - `:public` - Visible to everyone including end users

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret data", :private)
      %Trogon.Error.MetadataValue{value: "secret data", visibility: :private}

      iex> Trogon.Error.MetadataValue.new(123)
      %Trogon.Error.MetadataValue{value: "123", visibility: :internal}

  """

  @enforce_keys [:value, :visibility]
  defstruct [:value, :visibility]

  @type visibility :: :internal | :private | :public

  @type t :: %__MODULE__{
          value: String.t(),
          visibility: visibility()
        }

  @doc """
  Creates a new MetadataValue with the given value and visibility.

  The value will be converted to a string if it's not already one.

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret", :private)
      %Trogon.Error.MetadataValue{value: "secret", visibility: :private}

      iex> Trogon.Error.MetadataValue.new(123, :public)
      %Trogon.Error.MetadataValue{value: "123", visibility: :public}
  """
  @spec new(term(), visibility()) :: t()
  def new(value, visibility) when visibility in [:internal, :private, :public] do
    %__MODULE__{value: to_string(value), visibility: visibility}
  end

  @doc """
  Creates a new MetadataValue with the given value and default visibility.

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret")
      %Trogon.Error.MetadataValue{value: "secret", visibility: :internal}
  """
  @spec new(term()) :: t()
  def new(value) do
    new(value, :internal)
  end
end
