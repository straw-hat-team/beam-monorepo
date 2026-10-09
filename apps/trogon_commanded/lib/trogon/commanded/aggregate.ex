defmodule Trogon.Commanded.Aggregate do
  @moduledoc """
  Defines "Aggregate" modules.

  ## Features

  ### `v2`

  Commanded only ever reaches an aggregate state by starting from the empty
  struct and replaying events through `c:apply/2`. Any other way of building an
  aggregate creates a state production never reaches, so tests and callers
  relying on it can pass while the real system behaves differently.

  By default, aggregates are built on top of `Trogon.Commanded.Entity`, which
  generates `new/1`, `new!/1`, `changeset/2`, `validate/2`, and the
  `Ecto.Type` callbacks. Opt in to the `v2` feature to stop generating them:

      config :trogon_commanded, :features, v2: true

  With `v2` enabled, aggregates keep the `embedded_schema` struct, the
  identifier, `identity_prefix/0`, the `Jason.Encoder` derivation, and the
  `c:apply/2` fallback.

  The feature is read when your aggregate module compiles, through
  `Application.compile_env/4`, so Mix recompiles your aggregates when the value
  changes. Set it in `config/config.exs` (or another compile-time config file),
  not in `config/runtime.exs`.

  An aggregate can also opt in or out on its own, which takes precedence over
  the global config, so you can migrate one aggregate at a time:

      use Trogon.Commanded.Aggregate, identifier: :account_id, features: [v2: true]

  ### Marshalling a `v2` aggregate to and from JSON

  Use `Trogon.Commanded.EventStore.JsonbSerializer.Serializable`, which `v2`
  aggregates implement with Ecto's embedded schema round trip, so the data is
  loaded without going through a changeset:

      alias Trogon.Commanded.EventStore.JsonbSerializer.Serializable

      json =
        aggregate
        |> Serializable.serialize()
        |> Jason.encode!()

      aggregate = Serializable.deserialize(%MyApp.BankAccount{}, Jason.decode!(json))

  `Trogon.Commanded.EventStore.JsonbSerializer` uses the same protocol, so
  snapshots of `v2` aggregates round trip through it.
  """

  alias Trogon.Commanded.Features
  alias Trogon.Commanded.Helpers

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
            | [identity_prefix: String.t() | nil | {module(), atom()}, features: [v2: boolean()]]
        ) :: any()
  defmacro __using__(opts \\ []) do
    {opts, entity_opts} = Keyword.split(opts, [:identity_prefix, :features])

    identity_prefix =
      opts
      |> Keyword.get(:identity_prefix)
      |> Trogon.Commanded.StreamPrefix.resolve(__CALLER__)

    struct_definition =
      if Features.enabled?(__CALLER__, :v2, Keyword.get(opts, :features, [])) do
        schema(entity_opts)
      else
        quote generated: true do
          use Trogon.Commanded.Entity, unquote(entity_opts)
        end
      end

    quote generated: true do
      unquote(struct_definition)
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

  defp schema(opts) do
    unless Keyword.has_key?(opts, :identifier) do
      raise ArgumentError, "missing :identifier key"
    end

    {identifier, identifier_type} =
      opts
      |> Keyword.fetch!(:identifier)
      |> Helpers.get_primary_key()

    quote generated: true do
      use Ecto.Schema
      import PolymorphicEmbed, only: [polymorphic_embeds_one: 2, polymorphic_embeds_many: 2]

      @derive Jason.Encoder

      @typedoc """
      The key used to identify the aggregate.
      """
      @type identifier_key :: unquote(identifier)

      @primary_key {unquote(identifier), unquote(identifier_type), autogenerate: false}

      @doc """
      Returns the identity field of the aggregate.
      """
      @spec identifier :: identifier_key()
      def identifier do
        unquote(identifier)
      end

      defimpl Trogon.Commanded.EventStore.JsonbSerializer.Serializable do
        def serialize(aggregate), do: Ecto.embedded_dump(aggregate, :json)

        def deserialize(_aggregate, term), do: Ecto.embedded_load(@for, term, :json)
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
