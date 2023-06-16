defmodule OnePiece.Commanded.Aggregate do
  @moduledoc """
  Defines "Aggregate" modules.
  """

  @typedoc """
  A struct that represents an aggregate.
  """
  @type t :: struct()

  @type event :: struct()

  @doc """
  Apply a given event to the aggregate returning the new aggregate state.

  ## Example

      def apply(%MyAggregate{} = aggregate, %MyEvent{} = event) do
        aggregate
        |> Map.put(:name, event.name)
        |> Map.put(:description, event.description)
      end
  """
  @callback apply(aggregate :: t(), event :: event()) :: t()

  @doc """
  Convert the module into a `Aggregate` behaviour and a `t:t/0`.

  It adds an `apply/2` callback to the module as a fallback, return the aggregate as it is.

  ## Using

  - `OnePiece.Commanded.Entity`

  ## Usage

      defmodule Account do
        use OnePiece.Commanded.Aggregate, identifier: :name

        embedded_schema do
          field :description, :string
        end

        @impl OnePiece.Commanded.Aggregate
        def apply(%Account{} = aggregate, %AccountOpened{} = event) do
          aggregate
          |> Map.put(:name, event.name)
          |> Map.put(:description, event.description)
        end
      end
  """
  @spec __using__(opts :: []) :: any()
  defmacro __using__(opts \\ []) do
    quote do
      use OnePiece.Commanded.Entity, unquote(opts)
      @behaviour OnePiece.Commanded.Aggregate
      @before_compile OnePiece.Commanded.Aggregate
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @impl OnePiece.Commanded.Aggregate
      def apply(%unquote(env.module){} = aggregate, _event) do
        aggregate
      end
    end
  end
end
