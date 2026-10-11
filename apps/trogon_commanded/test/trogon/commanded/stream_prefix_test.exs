defmodule Trogon.Commanded.StreamPrefixTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.StreamPrefix

  @caller __ENV__

  describe "resolve/2" do
    test "returns nil when given nil" do
      assert StreamPrefix.resolve(nil, @caller) == nil
    end

    test "returns string as-is" do
      assert StreamPrefix.resolve("my-prefix-", @caller) == "my-prefix-"
    end

    test "resolves proto enum with default separator" do
      assert StreamPrefix.resolve(
               {Acme.Type.V1.StreamType, :STREAM_TYPE_BANK_ACCOUNT},
               @caller
             ) == "bank-account:"
    end

    test "resolves proto enum with custom separator" do
      assert StreamPrefix.resolve(
               {Acme.Type.V1.StreamType, :STREAM_TYPE_ORDER},
               @caller
             ) == "order#"
    end

    test "raises for missing enum value" do
      assert_raise ArgumentError, ~r/Enum value .* not found/, fn ->
        StreamPrefix.resolve(
          {Acme.Type.V1.StreamType, :STREAM_TYPE_NONEXISTENT},
          @caller
        )
      end
    end

    test "raises for enum value without extension" do
      assert_raise ArgumentError, ~r/No options found/, fn ->
        StreamPrefix.resolve(
          {Acme.Type.V1.StreamType, :STREAM_TYPE_UNSPECIFIED},
          @caller
        )
      end
    end
  end
end
