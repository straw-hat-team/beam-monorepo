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

  @typedoc """
  Raw input format for creating a MetadataValue.

  - Simple string: defaults to `:INTERNAL` visibility
  - Tuple `{value, visibility}`: explicit visibility control

      "user_id"              # => %MetadataValue{value: "user_id", visibility: :INTERNAL}
      {"secret", :PRIVATE}   # => %MetadataValue{value: "secret", visibility: :PRIVATE}
  """
  @type raw :: String.t() | {String.t(), visibility()}

  @doc """
  Creates a MetadataValue with explicit visibility. Non-string values are converted via `to_string/1`.

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
  Creates a MetadataValue with `:INTERNAL` visibility. See `new/2` for explicit visibility.

  ## Examples

      iex> Trogon.Error.MetadataValue.new("secret")
      %Trogon.Error.MetadataValue{value: "secret", visibility: :INTERNAL}
  """
  @spec new(term()) :: t()
  def new(value) do
    new(value, :INTERNAL)
  end
end
