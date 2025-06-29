defmodule Trogon.Commanded.Entity do
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

  If it's a tuple, the type must be a module that implements the `Trogon.Commanded.ValueObject` module or [`Ecto` built-in types](https://hexdocs.pm/ecto/Ecto.Schema.html#module-types-and-casting)
  """
  @type identifier_opt :: atom() | {key_name :: atom(), type :: atom()} | {key_name :: atom(), type :: module()}

  @type using_opts :: [identifier: identifier_opt()]

  @doc """
  Converts the module into an `t:t/0`.

  ## Identifier

  The `identifier` is used to identify the entity. It uses the `@primary_key` attribute to define the column and type.

  > #### Schema Field Registration {: .info}
  > `identifier` is automatically registered as a field in the `embedded_schema`.
  > Do not define the field in the `embedded_schema` yourself again.

  ## Using

  - `Trogon.Commanded.ValueObject`

  ## Usage

      defmodule MyEntity do
        use Trogon.Commanded.Entity, identifier: :id

        embedded_schema do
          # ...
        end
      end

  You can also define a custom type as the identifier:

      defmodule IdentityRoleId do
        use Trogon.Commanded.ValueObject

        embedded_schema do
          field :identity_id, :string
          field :role_id, :string
        end
      end

      defmodule IdentityRole do
        use Trogon.Commanded.Entity,
          identifier: {:id, IdentityRoleId}

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: using_opts()) :: any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :identifier) do
      raise ArgumentError, "missing :identifier key"
    end

    {identifier, identifier_type} =
      opts
      |> Keyword.fetch!(:identifier)
      |> Trogon.Commanded.Helpers.get_primary_key()

    quote generated: true do
      use Trogon.Commanded.ValueObject

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
