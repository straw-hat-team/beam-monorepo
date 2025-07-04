defmodule Trogon.Commanded.Aggregate do
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
  - `:identity_prefix` (optional) - The prefix to be used for the identity.

  ## Identifier

  The `identifier` is used to identify the aggregate. It uses the `@primary_key` attribute to define the column and type.

  > #### Schema Field Registration {: .info}
  > `identifier` is automatically registered as a field in the `embedded_schema`.
  > Do not define the field in the `embedded_schema` yourself again.

  ## Using

  - `Trogon.Commanded.Entity`

  ## Usage

      defmodule Account do
        use Trogon.Commanded.Aggregate, identifier: :name

        embedded_schema do
          field :description, :string
        end

        @impl Trogon.Commanded.Aggregate
        def apply(%Account{} = aggregate, %AccountOpened{} = event) do
          aggregate
          |> Map.put(:name, event.name)
          |> Map.put(:description, event.description)
        end
      end
  """
  @spec __using__(
          opts ::
            Trogon.Commanded.Entity.using_opts()
            | [identity_prefix: String.t() | nil]
        ) :: any()
  defmacro __using__(opts \\ []) do
    {opts, entity_opts} = Keyword.split(opts, [:identity_prefix])
    identity_prefix = Keyword.get(opts, :identity_prefix)

    quote generated: true do
      use Trogon.Commanded.Entity, unquote(entity_opts)
      @behaviour Trogon.Commanded.Aggregate
      @before_compile Trogon.Commanded.Aggregate

      @doc """
      Returns `#{inspect(unquote(identity_prefix))}` as the identity prefix.
      """
      @spec identity_prefix :: String.t() | nil
      def identity_prefix do
        unquote(identity_prefix)
      end
    end
  end

  defmacro __before_compile__(env) do
    quote do
      @impl Trogon.Commanded.Aggregate
      def apply(%unquote(env.module){} = aggregate, _event) do
        aggregate
      end
    end
  end
end
