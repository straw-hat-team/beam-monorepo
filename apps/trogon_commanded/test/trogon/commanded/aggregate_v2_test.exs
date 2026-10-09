defmodule Trogon.Commanded.AggregateV2Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trogon.Commanded.EventStore.JsonbSerializer
  alias Trogon.Commanded.EventStore.JsonbSerializer.Serializable
  alias Trogon.Commanded.TestSupport.CompileEnvTracer
  alias Trogon.Commanded.TestSupport.EmailContent
  alias Trogon.Commanded.TestSupport.ExampleAggregate
  alias Trogon.Commanded.TestSupport.MyAggregateOne
  alias Trogon.Commanded.TestSupport.MyAggregateV2
  alias Trogon.Commanded.TestSupport.MyEventOne
  alias Trogon.Commanded.TestSupport.MyEventTwo
  alias Trogon.Commanded.TestSupport.TransferableMoney

  @constructors [new: 1, new!: 1, changeset: 2, validate: 2]
  @ecto_type_callbacks [type: 0, cast: 1, load: 1, dump: 1, embed_as: 1, equal?: 2]
  @enforced_keys_helpers [__enforced_keys__: 0, __enforced_keys__?: 1]

  setup_all do
    Code.ensure_loaded!(MyAggregateOne)
    Code.ensure_loaded!(MyAggregateV2)
    :ok
  end

  describe "with the v2 feature disabled" do
    test "generates the constructor and changeset functions" do
      for {name, arity} <- @constructors ++ @ecto_type_callbacks ++ @enforced_keys_helpers do
        assert function_exported?(MyAggregateOne, name, arity), "expected #{name}/#{arity} to be defined"
      end
    end
  end

  describe "with the v2 feature enabled" do
    test "does not generate the constructor and changeset functions" do
      for {name, arity} <- @constructors ++ @ecto_type_callbacks ++ @enforced_keys_helpers do
        refute function_exported?(MyAggregateV2, name, arity), "expected #{name}/#{arity} to be undefined"
      end
    end

    test "does not implement Ecto.Type" do
      behaviours = Keyword.get_values(MyAggregateV2.__info__(:attributes), :behaviour)

      assert Trogon.Commanded.Aggregate in List.flatten(behaviours)
      refute Ecto.Type in List.flatten(behaviours)
    end

    test "keeps the embedded schema with its field defaults" do
      assert %MyAggregateV2{uuid: nil, name: nil, balance: 0, money: nil} = struct(MyAggregateV2)
      assert MyAggregateV2.__schema__(:fields) == [:uuid, :name, :balance, :money]
      assert MyAggregateV2.__schema__(:embeds) == [:money]
    end

    test "keeps the identifier as the primary key" do
      assert MyAggregateV2.identifier() == :uuid
      assert MyAggregateV2.__schema__(:primary_key) == [:uuid]
      assert MyAggregateV2.__schema__(:type, :uuid) == Ecto.UUID
    end

    test "keeps the identity prefix" do
      assert MyAggregateV2.identity_prefix() == "my-aggregate-v2-"
    end

    test "keeps the JSON encoding" do
      assert %MyAggregateV2{uuid: "123", name: "Hello"} |> Jason.encode!() |> Jason.decode!() ==
               %{"uuid" => "123", "name" => "Hello", "balance" => 0, "money" => nil}
    end

    test "applies events and falls back to returning the aggregate as is" do
      aggregate = struct(MyAggregateV2)

      assert %MyAggregateV2{uuid: "123", name: "Hello"} =
               MyAggregateV2.apply(aggregate, %MyEventOne{uuid: "123", name: "Hello"})

      assert MyAggregateV2.apply(aggregate, %MyEventTwo{}) == aggregate
    end

    test "requires an identifier" do
      assert_raise ArgumentError, "missing :identifier key", fn ->
        compile_aggregate(Trogon.Commanded.AggregateV2Test.MissingIdentifier, features: [v2: true])
      end
    end
  end

  describe "marshalling a v2 aggregate to and from JSON" do
    setup do
      aggregate = %ExampleAggregate{
        uuid: Ecto.UUID.generate(),
        name: "Hello",
        balance: 25,
        opened_at: ~U[2024-01-02 03:04:05.123456Z],
        status: :closed,
        money: %TransferableMoney{amount: 100, currency: :USD},
        contact: %EmailContent{subject: "Welcome", body: "Hi"}
      }

      %{aggregate: aggregate}
    end

    test "round trips through Ecto.embedded_dump/2 and Ecto.embedded_load/3", %{aggregate: aggregate} do
      json =
        aggregate
        |> Ecto.embedded_dump(:json)
        |> Jason.encode!()

      assert Ecto.embedded_load(ExampleAggregate, Jason.decode!(json), :json) == aggregate
    end

    test "round trips a snapshot through the JSONB serializer", %{aggregate: aggregate} do
      stored =
        aggregate
        |> JsonbSerializer.serialize()
        |> Jason.encode!()
        |> Jason.decode!()

      assert JsonbSerializer.deserialize(stored, type: Atom.to_string(ExampleAggregate)) == aggregate
    end

    test "has its own JSONB mapper implementation", %{aggregate: aggregate} do
      assert Serializable.impl_for(aggregate) == Module.concat(Serializable, ExampleAggregate)

      serialized = Serializable.serialize(aggregate)
      assert serialized == Ecto.embedded_dump(aggregate, :json)

      assert Serializable.deserialize(struct(ExampleAggregate), serialized |> Jason.encode!() |> Jason.decode!()) ==
               aggregate
    end
  end

  describe "the JSONB serializer with the v2 feature disabled" do
    test "dispatches aggregates to the fallback JSONB mapper" do
      aggregate = %MyAggregateOne{uuid: "123", name: "Hello"}

      assert Serializable.impl_for(aggregate) == Serializable.Any
      assert Serializable.serialize(aggregate) == aggregate
      assert Serializable.deserialize(%MyAggregateOne{}, %{"uuid" => "123", "name" => "Hello"}) == aggregate
    end

    test "keeps passing aggregates through and building them with new!/1" do
      aggregate = %MyAggregateOne{uuid: "123", name: "Hello"}

      assert JsonbSerializer.serialize(aggregate) == aggregate

      assert JsonbSerializer.deserialize(%{"uuid" => "123", "name" => "Hello"}, type: Atom.to_string(MyAggregateOne)) ==
               aggregate
    end
  end

  describe "reading the v2 feature from the application environment" do
    setup do
      previous = Application.fetch_env(:trogon_commanded, :features)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:trogon_commanded, :features, value)
          :error -> Application.delete_env(:trogon_commanded, :features)
        end
      end)
    end

    test "defaults to disabled" do
      Application.delete_env(:trogon_commanded, :features)

      module = compile_aggregate(Trogon.Commanded.AggregateV2Test.DefaultFeatures, identifier: :uuid)

      assert function_exported?(module, :new, 1)
      assert function_exported?(module, :changeset, 2)
    end

    test "enables v2 when configured" do
      Application.put_env(:trogon_commanded, :features, v2: true)

      module = compile_aggregate(Trogon.Commanded.AggregateV2Test.ConfiguredFeatures, identifier: :uuid)

      refute function_exported?(module, :new, 1)
      refute function_exported?(module, :changeset, 2)
    end

    test "tracks the feature as compile-time config so Mix recompiles the aggregate when it changes" do
      Application.put_env(:trogon_commanded, :features, v2: true)
      Process.register(self(), CompileEnvTracer)

      Code.put_compiler_option(:tracers, [CompileEnvTracer | Code.get_compiler_option(:tracers)])

      try do
        compile_aggregate(Trogon.Commanded.AggregateV2Test.TrackedFeatures, identifier: :uuid)
      after
        Code.put_compiler_option(:tracers, Code.get_compiler_option(:tracers) -- [CompileEnvTracer])
        Process.unregister(CompileEnvTracer)
      end

      assert_received {:compile_env, :trogon_commanded, [:features, :v2], {:ok, true}}
    end

    test "prefers the aggregate features option over the global config" do
      Application.put_env(:trogon_commanded, :features, v2: true)

      module =
        compile_aggregate(Trogon.Commanded.AggregateV2Test.OverriddenFeatures,
          identifier: :uuid,
          features: [v2: false]
        )

      assert function_exported?(module, :new, 1)
    end
  end

  defp compile_aggregate(module, opts) do
    quoted =
      quote do
        defmodule unquote(module) do
          use Trogon.Commanded.Aggregate, unquote(opts)

          embedded_schema do
            field :name, :string
          end
        end
      end

    capture_io(:stderr, fn -> send(self(), {:compiled, Code.compile_quoted(quoted)}) end)
    assert_received {:compiled, compiled}
    assert {^module, _binary} = List.keyfind(compiled, module, 0)
    module
  end
end
