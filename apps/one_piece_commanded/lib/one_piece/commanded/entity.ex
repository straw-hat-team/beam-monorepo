defmodule OnePiece.Commanded.Entity do
  @moduledoc """
  Defines "Entity" modules.
  """

  @typedoc """
  A struct that represents an entity.
  """
  @type t :: struct()

  @typedoc """
  The identity of an entity.
  """
  @type identity :: any()

  @typedoc """
  The identity key of the entity.

  If it's a tuple, the type must be a module that implements the `OnePiece.Commanded.ValueObject` module or [`Ecto` built-in types](https://hexdocs.pm/ecto/Ecto.Schema.html#module-types-and-casting)
  """
  @type identifier_opt :: atom() | {key_name :: atom(), type :: atom()} | {key_name :: atom(), type :: module()}

  @doc """
  Converts the module into an `t:t/0`.

  ## Using

  - `OnePiece.Commanded.ValueObject`

  ## Usage

      defmodule MyEntity do
        use OnePiece.Commanded.Entity, identifier: :id

        embedded_schema do
          # ...
        end
      end

  You can also define a custom type as the identifier:

      defmodule IdentityRoleId do
        use OnePiece.Commanded.ValueObject

        embedded_schema do
          field :identity_id, :string
          field :role_id, :string
        end
      end

      defmodule IdentityRole do
        use OnePiece.Commanded.Entity,
          identifier: {:id, IdentityRoleId}

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: [identifier: identifier_opt()]) :: any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :identifier) do
      raise ArgumentError, "missing :identifier key"
    end

    {identifier, identifier_type} =
      opts
      |> Keyword.fetch!(:identifier)
      |> OnePiece.Commanded.Helpers.get_primary_key()

    quote do
      use OnePiece.Commanded.ValueObject

      @typedoc """
      The key used to identify the entity.
      """
      @type identifier_key :: unquote(identifier)

      @primary_key {unquote(identifier), unquote(identifier_type), autogenerate: false}

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
