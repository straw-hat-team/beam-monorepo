defmodule OnePiece.Commanded.Command do
  @moduledoc """
  Defines "Command" modules.
  """

  @type t :: struct()

  @doc """
  Converts the module into an `Ecto.Schema`.

  It derives from `Jason.Encoder` and also adds some factory functions to create
  structs.

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
      use OnePiece.Commanded.ValueObject

      @typedoc """
      The key used to identify the aggregate.
      """
      @type aggregate_identifier_key :: unquote(aggregate_identifier)

      @primary_key {unquote(aggregate_identifier), :string, autogenerate: false}

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
