defmodule OnePiece.Commanded.Command do
  @moduledoc """
  Defines a module as a "Command". For more information about commands,
  please read the following:

  - [CQRS pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/cqrs)
  """

  alias OnePiece.Commanded.Command
  alias OnePiece.Commanded.Entity
  alias OnePiece.Commanded.Helpers

  @type t :: struct()

  @doc """
  Converts the module into an `Ecto.Schema`, and derive from `Jason.Encoder`.

  ## Usage

      defmodule MyCommand do
        use OnePiece.Commanded.Command, aggregate_identifier: :id

        embedded_schema do
          # ...
        end
      end
  """
  @spec __using__(opts :: [aggregate_identifier: atom()]) :: any()
  defmacro __using__(opts \\ []) do
    unless Keyword.has_key?(opts, :aggregate_identifier) do
      raise ArgumentError, "missing :aggregate_identifier key"
    end

    aggregate_identifier = Keyword.fetch!(opts, :aggregate_identifier)

    quote do
      use Ecto.Schema

      @typedoc """
      The key used to identify the aggregate.
      """
      @type aggregate_identifier_key :: unquote(aggregate_identifier)

      @aggregate_identifier_key unquote(aggregate_identifier)
      @primary_key {@aggregate_identifier_key, :string, autogenerate: false}
      @derive Jason.Encoder

      @doc """
      Creates a new `t:t/0` command.
      """
      @spec new(attrs :: map()) :: struct()
      def new(attrs) do
        Helpers.struct_from(attrs, __MODULE__)
      end

      @doc """
      Returns the aggregate identifier key.
      """
      @spec aggregate_identifier :: aggregate_identifier_key()
      def aggregate_identifier do
        @aggregate_identifier_key
      end

      @doc """
      Put the `value` into `t:t/0` aggregate identifier key.
      """
      @spec put_aggregate_id(command :: Command.t(), Entity.identity()) :: Command.t()
      def put_aggregate_id(command, value) do
        Map.put(command, @aggregate_identifier_key, value)
      end
    end
  end
end
