defmodule Trogon.Commanded.HelpersTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.Helpers

  doctest Trogon.Commanded.Helpers

  describe "ms_to_duration/1" do
    test "converts positive milliseconds to Duration" do
      assert Kernel.to_timeout(Helpers.ms_to_duration(100)) == 100
      assert Kernel.to_timeout(Helpers.ms_to_duration(1000)) == 1000
      assert Kernel.to_timeout(Helpers.ms_to_duration(1500)) == 1500
    end
  end

  describe "to_timeout/2" do
    test "returns positive integer unchanged" do
      assert Helpers.to_timeout(100, :timeout) == 100
      assert Helpers.to_timeout(1, :delay) == 1
    end

    test "converts Duration to milliseconds" do
      assert Helpers.to_timeout(Duration.new!(second: 1), :timeout) == 1000
      assert Helpers.to_timeout(Duration.new!(second: 5), :delay) == 5000
    end

    test "raises for zero with field name in message" do
      assert_raise ArgumentError, ~r/timeout must be positive, got: 0/, fn ->
        Helpers.to_timeout(0, :timeout)
      end
    end

    test "raises for negative integer with field name in message" do
      assert_raise ArgumentError, ~r/delay must be positive, got: -100/, fn ->
        Helpers.to_timeout(-100, :delay)
      end
    end

    test "raises for invalid type with field name in message" do
      assert_raise ArgumentError, ~r/timeout must be/, fn ->
        Helpers.to_timeout("1s", :timeout)
      end
    end
  end

  if Code.ensure_loaded?(Google.Protobuf) do
    describe "to_duration_or/2" do
      test "returns default when nil" do
        assert Helpers.to_duration_or(nil, 5000) == 5000
        assert Helpers.to_duration_or(nil, 100) == 100
      end

      test "converts Protobuf.Duration to Elixir Duration" do
        proto_duration = Google.Protobuf.from_duration(Duration.new!(second: 1))
        result = Helpers.to_duration_or(proto_duration, 5000)
        assert Kernel.to_timeout(result) == 1000
      end
    end
  end
end
