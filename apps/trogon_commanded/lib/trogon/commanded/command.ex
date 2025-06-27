defmodule Trogon.Commanded.Command do
  @moduledoc """
  Defines "Command" modules.
  """

  @typedoc """
  A struct that represents a command.
  """
  @type t :: struct()

  @typedoc """
  The aggregate identifier key of the event.

  If it's a tuple, the type must be a module that implements the `Trogon.Commanded.ValueObject` module or [`Ecto` built-in types](https://hexdocs.pm/ecto/Ecto.Schema.html#module-types-and-casting)
  """
  @type aggregate_identifier_opt ::
          atom() | {key_name :: atom(), type :: atom()} | {key_name :: atom(), type :: module()}

  @doc """
  Converts the module into an `t:t/0`.

  ### Options

  - `:aggregate_identifier` - The aggregate identifier key.
  - `:identity_prefix` (optional) - The prefix to be used for the identity.

  ## Aggregate Identifier

  The `aggregate_identifier` is used to identify the aggregate that the command is associated with. It uses the
  `@primary_key` attribute to define the column and type.

  > #### Schema Field Registration {: .info}
  > `aggregate_identifier` is automatically registered as a field in the `embedded_schema`.
  > Do not define the field in the `embedded_schema` yourself again.

  ## Using

  - `Trogon.Commanded.ValueObject`

  ## Usage

      defmodule MyCommand do
        use Trogon.Commanded.Command, aggregate_identifier: :id

        embedded_schema do
          # ...
        end
      end

  You can also define a custom type as the aggregate identifier:

      defmodule IdentityRoleId do
        use Trogon.Commanded.ValueObject

        embedded_schema do
          field :identity_id, :string
          field :role_id, :string
        end
      end

      defmodule AssignRole do
        use Trogon.Commanded.Command,
          aggregate_identifier: {:id, IdentityRoleId}

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: [aggregate_identifier: aggregate_identifier_opt(), identity_prefix: String.t() | nil]) ::
          any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :aggregate_identifier) do
      raise ArgumentError, "missing :aggregate_identifier key"
    end

    identity_prefix = Keyword.get(opts, :identity_prefix)

    {aggregate_identifier, aggregate_identifier_type} =
      opts
      |> Keyword.fetch!(:aggregate_identifier)
      |> Trogon.Commanded.Helpers.get_primary_key()

    quote generated: true do
      use Trogon.Commanded.ValueObject

      @typedoc """
      The key used to identify the aggregate.
      """
      @type aggregate_identifier_key :: unquote(aggregate_identifier)

      @primary_key {unquote(aggregate_identifier), unquote(aggregate_identifier_type), autogenerate: false}

      @doc """
      Returns the aggregate identifier key.
      """
      @spec aggregate_identifier :: aggregate_identifier_key()
      def aggregate_identifier do
        unquote(aggregate_identifier)
      end

      @doc """
      Returns `#{inspect(unquote(identity_prefix))}` as the identity prefix.
      """
      @spec identity_prefix :: String.t() | nil
      def identity_prefix do
        unquote(identity_prefix)
      end
    end
  end
end
