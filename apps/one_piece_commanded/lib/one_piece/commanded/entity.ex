defmodule OnePiece.Commanded.Entity do
  @moduledoc """
  Defines a module as an "Entity" in the context of Domain-Driven Design.
  """

  @typedoc """
  The identity of an entity.
  """
  @type identity :: String.t()

  @doc """
  Converts the module into an `Ecto.Schema`, and derive from `Jason.Encoder`.

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
      use Ecto.Schema

      @identifier_key unquote(identifier)
      @primary_key {@identifier_key, :string, autogenerate: false}
      @derive Jason.Encoder

      @typedoc """
      The key used to identify the entity.
      """
      @type identifier_key :: unquote(identifier)

      @doc """
      Returns the identity field of the entity.
      """
      @spec identifier :: identifier_key()
      def identifier do
        @identifier_key
      end
    end
  end
end
