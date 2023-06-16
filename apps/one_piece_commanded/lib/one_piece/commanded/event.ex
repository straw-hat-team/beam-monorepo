defmodule OnePiece.Commanded.Event do
  @moduledoc """
  Defines "Event" modules.
  """

  @typedoc """
  A struct that represents an event.
  """
  @type t :: struct()

  @typedoc """
  The aggregate identifier key of the event.

  If it's a tuple, the type must be a module that implements the `OnePiece.Commanded.ValueObject` module or [`Ecto` built-in types](https://hexdocs.pm/ecto/Ecto.Schema.html#module-types-and-casting)
  """
  @type aggregate_identifier_opt ::
          atom() | {key_name :: atom(), type :: atom()} | {key_name :: atom(), type :: module()}

  @doc """
  Converts the module into an `t:t/0`.

  ## Using

  - `OnePiece.Commanded.ValueObject`

  ## Usage

      defmodule MyEvent do
        use OnePiece.Commanded.Event, aggregate_identifier: :id

        embedded_schema do
          # ...
        end
      end

  You can also define a custom type as the aggregate identifier:

      defmodule IdentityRoleId do
        use OnePiece.Commanded.ValueObject

        embedded_schema do
          field :identity_id, :string
          field :role_id, :string
        end
      end

      defmodule IdentityRoleAssigned do
        use OnePiece.Commanded.Event,
          aggregate_identifier: {:id, IdentityRoleId}

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: [aggregate_identifier: aggregate_identifier_opt()]) :: any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :aggregate_identifier) do
      raise ArgumentError, "missing :aggregate_identifier key"
    end

    {aggregate_identifier, aggregate_identifier_type} =
      opts
      |> Keyword.fetch!(:aggregate_identifier)
      |> OnePiece.Commanded.Helpers.get_primary_key()

    quote do
      use OnePiece.Commanded.ValueObject

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
    end
  end
end
