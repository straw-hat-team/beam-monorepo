defmodule Trogon.Ecto.Type.DurationTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.TestSupport.WithDuration

  doctest Trogon.Ecto.Type.Duration

  describe "embed_as/1" do
    test "a nested duration is dumped to its ISO 8601 string, not left as a struct" do
      value_object = struct!(WithDuration, length: Duration.new!(second: 10))

      assert {:ok, %{length: "PT10S"}} = WithDuration.dump(value_object)
    end

    test "the dumped value object is JSON encodable" do
      value_object = struct!(WithDuration, length: Duration.new!(second: 10))
      {:ok, dumped} = WithDuration.dump(value_object)

      assert {:ok, ~s({"length":"PT10S"})} = Jason.encode(dumped)
    end

    test "a nil duration survives the round trip" do
      value_object = struct!(WithDuration, length: nil)

      assert {:ok, %{length: nil}} = WithDuration.dump(value_object)
    end
  end
end
