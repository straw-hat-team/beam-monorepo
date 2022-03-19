defmodule OnePiece.Commanded.Event do
  @moduledoc """
  Defines a module as a "Event" in terms of Event Sourcing context. For more
  information about Event Sourcing, please read the following:

  - [Event Sourcing pattern](https://docs.microsoft.com/en-us/azure/architecture/patterns/event-sourcing)
  """

  alias OnePiece.Commanded.Helpers

  @type t :: struct()

  @doc """
  Converts the module into an `Ecto.Schema`, and derive from `Jason.Encoder`.

  ## Usage

      defmodule MyEvent do
        use OnePiece.Commanded.Event, aggregate_identifier: :id

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
    end
  end
end
