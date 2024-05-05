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

  ### Options

  - `:identifier` - The aggregate identifier key.
  - `:stream_prefix` (optional) - The prefix to be used for the identity.

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
  @spec __using__(
          opts ::
            OnePiece.Commanded.Entity.using_opts()
            | [stream_prefix: String.t() | nil]
        ) :: any()
  defmacro __using__(opts \\ []) do
    {opts, entity_opts} = Keyword.split(opts, [:stream_prefix])
    stream_prefix = Keyword.get(opts, :stream_prefix)

    quote do
      use OnePiece.Commanded.Entity, unquote(entity_opts)
      @behaviour OnePiece.Commanded.Aggregate
      @before_compile OnePiece.Commanded.Aggregate

      @doc """
      Returns `#{inspect(unquote(stream_prefix))}` as the identity prefix.
      """
      @spec stream_prefix :: String.t() | nil
      def stream_prefix do
        unquote(stream_prefix)
      end
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
