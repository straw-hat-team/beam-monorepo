defmodule Trogon.Ecto.DurationTypeTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.DurationType
  alias Trogon.Ecto.TestSupport.WithDuration
  alias Trogon.Ecto.TestSupport.WithMapDuration

  doctest DurationType

  @durations [
    Duration.new!(year: 1),
    Duration.new!(week: 2),
    Duration.new!(hour: 1),
    Duration.new!(minute: 90),
    Duration.new!(second: 10),
    Duration.new!(microsecond: {500_000, 6})
  ]

  describe "init/1" do
    test "raises ArgumentError for an unsupported format" do
      assert_raise ArgumentError, ~r/invalid :format :bogus/, fn ->
        DurationType.init(format: :bogus)
      end
    end

    test "raises ArgumentError for an unsupported equality" do
      assert_raise ArgumentError, ~r/invalid :equality :bogus/, fn ->
        DurationType.init(format: :native, equality: :bogus)
      end
    end

    test "requires :equality for :native, which has no safe default" do
      assert_raise ArgumentError, ~r/missing :equality/, fn ->
        DurationType.init(format: :native)
      end
    end

    test "defaults :equality to :strict for the formats that preserve precision" do
      assert DurationType.init([]) == %{format: :iso8601, equality: :strict}
      assert DurationType.init(format: :map) == %{format: :map, equality: :strict}
    end

    test "keeps an explicit :equality for the other formats" do
      assert DurationType.init(format: :map, equality: :storage) ==
               %{format: :map, equality: :storage}
    end
  end

  describe "round trip" do
    test "every duration round-trips exactly through :iso8601" do
      assert_round_trips(:iso8601)
    end

    test "every duration round-trips exactly through :map" do
      assert_round_trips(:map)
    end

    defp assert_round_trips(format) do
      params = DurationType.init(format: format)

      for duration <- @durations do
        assert {:ok, dumped} = DurationType.dump(duration, & &1, params)
        assert {:ok, loaded} = DurationType.load(dumped, & &1, params)
        assert loaded == duration
      end
    end
  end

  describe "dump/3 :map shape" do
    test "omits zero-valued components" do
      params = DurationType.init(format: :map)

      assert {:ok, %{"minute" => 90}} = DurationType.dump(Duration.new!(minute: 90), & &1, params)
    end

    test "omits a zero microsecond" do
      params = DurationType.init(format: :map)

      assert {:ok, %{"second" => 10}} = DurationType.dump(Duration.new!(second: 10), & &1, params)
    end

    test "keeps a non-zero microsecond" do
      params = DurationType.init(format: :map)

      assert {:ok, %{"microsecond" => [500_000, 6]}} =
               DurationType.dump(Duration.new!(microsecond: {500_000, 6}), & &1, params)
    end
  end

  describe "load/3 across formats" do
    test "loads a component map even when the field is configured for :iso8601" do
      params = DurationType.init([])

      assert {:ok, %Duration{second: 10}} = DurationType.load(%{"second" => 10}, & &1, params)
    end

    test "loads an ISO 8601 string even when the field is configured for :map" do
      params = DurationType.init(format: :map)

      assert {:ok, %Duration{second: 10}} = DurationType.load("PT10S", & &1, params)
    end

    test "loads a component map with atom keys" do
      params = DurationType.init([])

      assert {:ok, %Duration{second: 10}} = DurationType.load(%{second: 10}, & &1, params)
    end

    test "loads a component map with a non-zero microsecond" do
      params = DurationType.init(format: :map)

      assert {:ok, %Duration{microsecond: {500_000, 6}}} =
               DurationType.load(%{"microsecond" => [500_000, 6]}, & &1, params)
    end

    test "loads a Duration struct as-is" do
      params = DurationType.init([])
      duration = Duration.new!(second: 10)

      assert {:ok, ^duration} = DurationType.load(duration, & &1, params)
    end

    test "loads nil as nil" do
      params = DurationType.init([])

      assert {:ok, nil} = DurationType.load(nil, & &1, params)
    end

    test "rejects an unparsable value" do
      params = DurationType.init([])

      assert :error = DurationType.load("random value", & &1, params)
    end
  end

  describe "cast/2" do
    setup do
      %{params: DurationType.init([])}
    end

    test "accepts a Duration struct", %{params: params} do
      duration = Duration.new!(second: 10)

      assert {:ok, ^duration} = DurationType.cast(duration, params)
    end

    test "accepts an ISO 8601 string", %{params: params} do
      assert {:ok, %Duration{second: 10}} = DurationType.cast("PT10S", params)
    end

    test "accepts a component map with string keys", %{params: params} do
      assert {:ok, %Duration{second: 10}} = DurationType.cast(%{"second" => 10}, params)
    end

    test "accepts a component map with atom keys", %{params: params} do
      assert {:ok, %Duration{second: 10}} = DurationType.cast(%{second: 10}, params)
    end

    test "accepts a component map with microsecond as a two-element list", %{params: params} do
      assert {:ok, %Duration{microsecond: {500_000, 6}}} =
               DurationType.cast(%{"microsecond" => [500_000, 6]}, params)
    end

    test "accepts nil", %{params: params} do
      assert {:ok, nil} = DurationType.cast(nil, params)
    end

    test "rejects an invalid ISO 8601 string", %{params: params} do
      assert :error = DurationType.cast("random value", params)
    end

    test "rejects a map with an unknown component key", %{params: params} do
      assert :error = DurationType.cast(%{"bogus" => 1}, params)
    end

    test "rejects a map with an invalid component value", %{params: params} do
      assert :error = DurationType.cast(%{"second" => "not a number"}, params)
    end

    test "rejects a value of an unsupported type", %{params: params} do
      assert :error = DurationType.cast(123, params)
    end

    test "rejects an out of range microsecond precision", %{params: params} do
      assert :error = DurationType.cast(%{"microsecond" => [1, 99]}, params)
      assert :error = DurationType.cast(%{"microsecond" => [1, -1]}, params)
      assert :error = DurationType.cast(%{"microsecond" => ["x", 6]}, params)
    end

    test "returns :error rather than raising on malformed component values", %{params: params} do
      for value <- [nil, "abc", 1.5, :atom, [], [1], [1, 2, 3], %{}, true] do
        assert :error = DurationType.cast(%{"second" => value}, params)
        assert :error = DurationType.cast(%{"microsecond" => value}, params)
      end
    end
  end

  describe "schema field declarations" do
    test "bare `field :x, Trogon.Ecto.DurationType` casts an ISO 8601 string" do
      assert {:ok, %WithDuration{length: %Duration{second: 10}}} = WithDuration.new(%{length: "PT10S"})
    end

    test "`field :x, Trogon.Ecto.DurationType, format: :map` casts a component map" do
      assert {:ok, %WithMapDuration{length: %Duration{second: 10}}} =
               WithMapDuration.new(%{length: %{"second" => 10}})
    end
  end

  describe "embed_as/2" do
    test "a nested :iso8601 duration is dumped to its ISO 8601 string, not left as a struct" do
      value_object = struct!(WithDuration, length: Duration.new!(second: 10))

      assert {:ok, %{length: "PT10S"}} = WithDuration.dump(value_object)
    end

    test "a nested :map duration is dumped to a component map" do
      value_object = struct!(WithMapDuration, length: Duration.new!(minute: 90))

      assert {:ok, %{length: %{"minute" => 90}}} = WithMapDuration.dump(value_object)
    end

    test "the dumped :iso8601 value object is JSON encodable" do
      value_object = struct!(WithDuration, length: Duration.new!(second: 10))
      {:ok, dumped} = WithDuration.dump(value_object)

      assert {:ok, ~s({"length":"PT10S"})} = Jason.encode(dumped)
    end

    test "the dumped :map value object is JSON encodable" do
      value_object = struct!(WithMapDuration, length: Duration.new!(microsecond: {500_000, 6}))
      {:ok, dumped} = WithMapDuration.dump(value_object)

      assert {:ok, ~s({"length":{"microsecond":[500000,6]}})} = Jason.encode(dumped)
    end

    test "a nil duration survives the round trip" do
      value_object = struct!(WithDuration, length: nil)

      assert {:ok, %{length: nil}} = WithDuration.dump(value_object)
    end

    test "raises for :native, since a Duration struct cannot be JSON encoded" do
      params = DurationType.init(format: :native, equality: :storage)

      assert_raise ArgumentError, ~r/cannot be stored inside an embed or value object/, fn ->
        DurationType.embed_as(:json, params)
      end
    end
  end

  describe ":native format" do
    setup do
      %{params: DurationType.init(format: :native, equality: :storage)}
    end

    test "type/1 is :duration", %{params: params} do
      assert DurationType.type(params) == :duration
    end

    test "dump/3 passes the Duration struct through as-is", %{params: params} do
      duration = Duration.new!(second: 10)

      assert {:ok, ^duration} = DurationType.dump(duration, & &1, params)
    end

    test "dump/3 passes nil through", %{params: params} do
      assert {:ok, nil} = DurationType.dump(nil, & &1, params)
    end

    test "cast/2 still accepts an ISO 8601 string, unlike Ecto's built-in :duration", %{params: params} do
      assert {:ok, %Duration{second: 10}} = DurationType.cast("PT10S", params)
    end

    test "load/3 accepts a Duration struct as-is", %{params: params} do
      duration = Duration.new!(second: 10)

      assert {:ok, ^duration} = DurationType.load(duration, & &1, params)
    end

    test "load/3 converts a Postgrex.Interval, as decoded by default from an interval column", %{
      params: params
    } do
      interval = %Postgrex.Interval{months: 14, days: 3, secs: 61, microsecs: 500_000}

      assert {:ok, %Duration{month: 14, day: 3, second: 61, microsecond: {500_000, 6}}} =
               DurationType.load(interval, & &1, params)
    end
  end

  describe "equal?/3" do
    setup do
      %{
        native: DurationType.init(format: :native, equality: :storage),
        native_strict: DurationType.init(format: :native, equality: :strict),
        iso8601: DurationType.init([])
      }
    end

    test "treats year and month as equal for :native, as PostgreSQL stores them", %{native: p} do
      assert DurationType.equal?(Duration.new!(year: 1), Duration.new!(month: 12), p)
      assert DurationType.equal?(Duration.new!(year: 2, month: 1), Duration.new!(month: 25), p)
    end

    test "treats week and day as equal for :native", %{native: p} do
      assert DurationType.equal?(Duration.new!(week: 2), Duration.new!(day: 14), p)
      assert DurationType.equal?(Duration.new!(week: 1, day: 3), Duration.new!(day: 10), p)
    end

    test "treats sub-day components as equal for :native", %{native: p} do
      assert DurationType.equal?(Duration.new!(hour: 1), Duration.new!(minute: 60), p)
      assert DurationType.equal?(Duration.new!(minute: 1), Duration.new!(second: 60), p)
      assert DurationType.equal?(Duration.new!(hour: 1, minute: 30), Duration.new!(minute: 90), p)
    end

    test "does not conflate components PostgreSQL keeps separate", %{native: p} do
      refute DurationType.equal?(Duration.new!(month: 1), Duration.new!(day: 30), p)
      refute DurationType.equal?(Duration.new!(day: 1), Duration.new!(hour: 24), p)
    end

    test "keeps structural equality for :iso8601, which preserves the unit", %{iso8601: p} do
      refute DurationType.equal?(Duration.new!(year: 1), Duration.new!(month: 12), p)
      refute DurationType.equal?(Duration.new!(minute: 1), Duration.new!(second: 60), p)
      assert DurationType.equal?(Duration.new!(second: 10), Duration.new!(second: 10), p)
    end

    test "survives a simulated :native write and read without reporting a change", %{native: p} do
      for original <- [
            Duration.new!(year: 1, week: 2, minute: 90),
            Duration.new!(second: 10),
            Duration.new!(hour: 1, minute: 30),
            Duration.new!(microsecond: {500_000, 2})
          ] do
        assert DurationType.equal?(original, simulate_round_trip(original, p), p)
      end
    end

    test "reports a change on every save under :strict, which is why :native must choose",
         %{native_strict: p} do
      original = Duration.new!(second: 10)

      refute DurationType.equal?(original, simulate_round_trip(original, p), p)
    end

    test "collapses the units PostgreSQL drops on the way in", %{native: p} do
      original = Duration.new!(year: 1, week: 2, minute: 90)
      reloaded = simulate_round_trip(original, p)

      refute reloaded == original
      assert reloaded == Duration.new!(month: 12, day: 14, second: 5400, microsecond: {0, 6})
    end

    defp simulate_round_trip(duration, params) do
      {:ok, dumped} = DurationType.dump(duration, & &1, params)

      encoded = %Postgrex.Interval{
        months: 12 * dumped.year + dumped.month,
        days: 7 * dumped.week + dumped.day,
        secs: 3600 * dumped.hour + 60 * dumped.minute + dumped.second,
        microsecs: elem(dumped.microsecond, 0)
      }

      {:ok, reloaded} = DurationType.load(encoded, & &1, params)
      reloaded
    end

    test "ignores microsecond precision for :native under :storage", %{native: p} do
      assert DurationType.equal?(
               Duration.new!(microsecond: {500_000, 2}),
               Duration.new!(microsecond: {500_000, 6}),
               p
             )

      refute DurationType.equal?(
               Duration.new!(microsecond: {1, 6}),
               Duration.new!(microsecond: {2, 6}),
               p
             )
    end

    test "keeps microsecond precision significant for :native under :strict",
         %{native_strict: p} do
      refute DurationType.equal?(
               Duration.new!(microsecond: {500_000, 2}),
               Duration.new!(microsecond: {500_000, 6}),
               p
             )
    end

    test "does not fold units for :native under :strict", %{native_strict: p} do
      refute DurationType.equal?(Duration.new!(year: 1), Duration.new!(month: 12), p)
      assert DurationType.equal?(Duration.new!(year: 1), Duration.new!(year: 1), p)
    end

    test "normalizes negative durations for :native", %{native: p} do
      assert DurationType.equal?(Duration.new!(minute: -1), Duration.new!(second: -60), p)
      assert DurationType.equal?(Duration.new!(year: -1), Duration.new!(month: -12), p)
    end
  end
end
