defmodule Trogon.Error.MetadataValueTest do
  alias Trogon.Error.MetadataValue

  use ExUnit.Case, async: true
  doctest MetadataValue

  describe "new/2" do
    test "creates a MetadataValue with string value" do
      metadata = MetadataValue.new("secret", :PRIVATE)
      assert %MetadataValue{value: "secret", visibility: :PRIVATE} = metadata
    end

    test "converts non-string values to strings" do
      metadata = MetadataValue.new(123, :PUBLIC)
      assert %MetadataValue{value: "123", visibility: :PUBLIC} = metadata
    end

    test "handles atom values" do
      metadata = MetadataValue.new(:atom_value, :INTERNAL)
      assert %MetadataValue{value: "atom_value", visibility: :INTERNAL} = metadata
    end

    test "handles nil values" do
      metadata = MetadataValue.new(nil, :PUBLIC)
      assert %MetadataValue{value: "", visibility: :PUBLIC} = metadata
    end

    test "handles empty string values" do
      metadata = MetadataValue.new("", :PRIVATE)
      assert %MetadataValue{value: "", visibility: :PRIVATE} = metadata
    end

    test "handles boolean values" do
      metadata_true = MetadataValue.new(true, :PUBLIC)
      metadata_false = MetadataValue.new(false, :INTERNAL)

      assert %MetadataValue{value: "true", visibility: :PUBLIC} = metadata_true
      assert %MetadataValue{value: "false", visibility: :INTERNAL} = metadata_false
    end

    test "handles charlist values" do
      metadata = MetadataValue.new(~c"charlist", :PRIVATE)
      assert %MetadataValue{value: "charlist", visibility: :PRIVATE} = metadata
    end

    test "raises error for invalid visibility" do
      assert_raise FunctionClauseError, fn ->
        MetadataValue.new("value", :invalid)
      end
    end
  end

  describe "new/1" do
    test "uses default internal visibility" do
      metadata = MetadataValue.new("test")
      assert %MetadataValue{value: "test", visibility: :INTERNAL} = metadata
    end

    test "handles various data types with default visibility" do
      test_cases = [
        {"string", "string"},
        {123, "123"},
        {:atom, "atom"},
        {true, "true"},
        {nil, ""}
      ]

      for {input, expected_value} <- test_cases do
        metadata = MetadataValue.new(input)
        assert %MetadataValue{value: ^expected_value, visibility: :INTERNAL} = metadata
      end
    end

    test "handles charlist data with default visibility" do
      metadata_charlist = MetadataValue.new(~c"charlist")
      assert %MetadataValue{value: "charlist", visibility: :INTERNAL} = metadata_charlist
    end
  end
end
