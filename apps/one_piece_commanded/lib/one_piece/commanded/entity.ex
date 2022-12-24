defmodule OnePiece.Commanded.Entity do
  @moduledoc """
  Defines "Entity" modules.
  """

  @typedoc """
  The identity of an entity.
  """
  @type identity :: String.t()

  @doc """
  Converts the module into an `Ecto.Schema`.

  It derives from `Jason.Encoder` and also adds some factory functions to create
  structs.

  ## Usage

      defmodule MyEntity do
        use OnePiece.Commanded.Entity, identifier: :id

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: [identifier: atom()]) :: any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :identifier) do
      raise ArgumentError, "missing :identifier key"
    end

    identifier = Keyword.fetch!(opts, :identifier)

    quote do
      use OnePiece.Commanded.ValueObject

      @typedoc """
      The key used to identify the entity.
      """
      @type identifier_key :: unquote(identifier)

      @primary_key {unquote(identifier), :string, autogenerate: false}

      @doc """
      Returns the identity field of the entity.
      """
      @spec identifier :: identifier_key()
      def identifier do
        unquote(identifier)
      end
    end
  end
end
