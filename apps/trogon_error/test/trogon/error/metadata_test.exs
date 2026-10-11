defmodule Trogon.Error.MetadataTest do
  alias Trogon.Error.{Metadata, MetadataValue}

  use ExUnit.Case, async: true
  import Trogon.Error.Metadata, only: [is_empty_metadata: 1]

  doctest Metadata

  describe "new/1" do
    test "creates empty metadata efficiently" do
      metadata = Metadata.new(%{})
      assert %Metadata{entries: entries} = metadata
      assert entries == %{}
      assert map_size(entries) == 0
    end

    test "creates metadata with simple values" do
      metadata = Metadata.new(%{"key" => "value"})
      assert %Metadata{entries: entries} = metadata
      assert entries["key"] == %MetadataValue{value: "value", visibility: :INTERNAL}
    end

    test "creates metadata with tuple format" do
      metadata = Metadata.new(%{"secret" => {"api-key", :PRIVATE}})
      assert %Metadata{entries: entries} = metadata
      assert entries["secret"] == %MetadataValue{value: "api-key", visibility: :PRIVATE}
    end

    test "creates metadata with MetadataValue structs" do
      value = MetadataValue.new("test", :PUBLIC)
      metadata = Metadata.new(%{"existing" => value})
      assert %Metadata{entries: entries} = metadata
      assert entries["existing"] == value
    end

    test "converts atom keys to strings" do
      metadata = Metadata.new(%{user_id: "123"})
      assert %Metadata{entries: entries} = metadata
      assert entries["user_id"] == %MetadataValue{value: "123", visibility: :INTERNAL}
    end

    test "handles mixed value types" do
      metadata =
        Metadata.new(%{
          "simple" => "value",
          "tuple" => {"secret", :PRIVATE},
          "struct" => MetadataValue.new("existing", :PUBLIC),
          atom_key: 42
        })

      assert %Metadata{entries: entries} = metadata
      assert entries["simple"] == %MetadataValue{value: "value", visibility: :INTERNAL}
      assert entries["tuple"] == %MetadataValue{value: "secret", visibility: :PRIVATE}
      assert entries["struct"] == %MetadataValue{value: "existing", visibility: :PUBLIC}
      assert entries["atom_key"] == %MetadataValue{value: "42", visibility: :INTERNAL}
    end
  end

  describe "merge/2" do
    test "merges two metadata structs" do
      metadata1 = Metadata.new(%{"key1" => "value1"})
      metadata2 = Metadata.new(%{"key2" => "value2"})

      merged = Metadata.merge(metadata1, metadata2)

      assert %Metadata{entries: entries} = merged
      assert entries["key1"] == %MetadataValue{value: "value1", visibility: :INTERNAL}
      assert entries["key2"] == %MetadataValue{value: "value2", visibility: :INTERNAL}
    end

    test "second metadata overwrites first on key conflicts" do
      metadata1 = Metadata.new(%{"key" => "value1"})
      metadata2 = Metadata.new(%{"key" => "value2"})

      merged = Metadata.merge(metadata1, metadata2)

      assert %Metadata{entries: entries} = merged
      assert entries["key"] == %MetadataValue{value: "value2", visibility: :INTERNAL}
    end

    test "returns empty metadata when both sides are empty" do
      empty = Metadata.new()

      assert Metadata.merge(empty, empty) == %Metadata{entries: %{}}
    end

    test "returns left side when right side is empty" do
      left = Metadata.new(%{"key" => "value"})
      empty = Metadata.new()

      merged = Metadata.merge(left, empty)

      assert merged == left
    end

    test "returns right side when left side is empty" do
      empty = Metadata.new()
      right = Metadata.new(%{"key" => "value"})

      merged = Metadata.merge(empty, right)

      assert merged == right
    end
  end

  describe "from_field_specs/2" do
    test "builds metadata from field specs with nil policy" do
      specs = [{"userId", :user_id, :PUBLIC, nil}]
      proto = %{user_id: "user-123", __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["userId"].value == "user-123"
      assert metadata["userId"].visibility == :PUBLIC
    end

    test "uses default value when proto field is empty" do
      specs = [{"service", :service, :PUBLIC, {:default, "user-api"}}]
      proto = %{service: "", __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["service"].value == "user-api"
    end

    test "uses proto field value over default when present" do
      specs = [{"service", :service, :PUBLIC, {:default, "user-api"}}]
      proto = %{service: "billing-api", __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["service"].value == "billing-api"
    end

    test "uses default value when proto field is nil" do
      specs = [{"service", :service, :PUBLIC, {:default, "user-api"}}]
      proto = %{service: nil, __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["service"].value == "user-api"
    end

    test "uses fixed value regardless of proto field" do
      specs = [{"region", :region, :PUBLIC, {:fixed, "us-east-1"}}]
      proto = %{region: "eu-west-1", __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["region"].value == "us-east-1"
    end

    test "builds entries for multiple field specs" do
      specs = [
        {"userId", :user_id, :PUBLIC, nil},
        {"trace", :trace, :INTERNAL, nil},
        {"service", :service, :PUBLIC, {:default, "default-svc"}},
        {"region", :region, :PRIVATE, {:fixed, "us-east-1"}}
      ]

      proto = %{user_id: "u-1", trace: "t-1", service: "", region: "ignored", __struct__: FakeProto}

      metadata = Metadata.from_field_specs(specs, proto)

      assert metadata["userId"] == %MetadataValue{value: "u-1", visibility: :PUBLIC}
      assert metadata["trace"] == %MetadataValue{value: "t-1", visibility: :INTERNAL}
      assert metadata["service"] == %MetadataValue{value: "default-svc", visibility: :PUBLIC}
      assert metadata["region"] == %MetadataValue{value: "us-east-1", visibility: :PRIVATE}
    end
  end

  describe "Access behavior" do
    setup do
      metadata =
        Metadata.new(%{
          "public" => {"visible", :PUBLIC},
          "private" => {"hidden", :PRIVATE},
          "internal" => "default"
        })

      {:ok, metadata: metadata}
    end

    test "fetch/2 returns metadata values", %{metadata: metadata} do
      assert {:ok, value} = Metadata.fetch(metadata, "public")
      assert value == %MetadataValue{value: "visible", visibility: :PUBLIC}

      assert :error = Metadata.fetch(metadata, "nonexistent")
    end

    test "supports bracket access", %{metadata: metadata} do
      assert metadata["public"] == %MetadataValue{value: "visible", visibility: :PUBLIC}
      assert metadata["private"] == %MetadataValue{value: "hidden", visibility: :PRIVATE}
      assert metadata["internal"] == %MetadataValue{value: "default", visibility: :INTERNAL}
      assert metadata["nonexistent"] == nil
    end

    test "supports get_and_update/3", %{metadata: metadata} do
      {old_value, new_metadata} =
        Metadata.get_and_update(metadata, "public", fn value ->
          {value, %{value | visibility: :INTERNAL}}
        end)

      assert old_value == %MetadataValue{value: "visible", visibility: :PUBLIC}
      assert new_metadata["public"] == %MetadataValue{value: "visible", visibility: :INTERNAL}
    end

    test "supports pop/2", %{metadata: metadata} do
      {popped_value, new_metadata} = Metadata.pop(metadata, "private")

      assert popped_value == %MetadataValue{value: "hidden", visibility: :PRIVATE}
      assert new_metadata["private"] == nil
      assert map_size(new_metadata.entries) == 2
    end
  end

  describe "is_empty_metadata/1 guard" do
    test "works correctly in function guards" do
      alias Trogon.Error.TestSupport.MetadataTestGuards

      empty_metadata = Metadata.new(%{})
      non_empty_metadata = Metadata.new(%{"key" => "value"})

      assert MetadataTestGuards.test_empty(empty_metadata) == :empty
      assert MetadataTestGuards.test_empty(non_empty_metadata) == :not_empty
    end

    test "correctly identifies empty vs non-empty metadata" do
      alias Trogon.Error.TestSupport.MetadataTestGuards

      assert MetadataTestGuards.test_empty(Metadata.new(%{})) == :empty

      assert MetadataTestGuards.test_empty(Metadata.new(%{"key" => "value"})) == :not_empty
      assert MetadataTestGuards.test_empty(Metadata.new(%{"a" => "1", "b" => "2"})) == :not_empty
      assert MetadataTestGuards.test_empty(Metadata.new(%{"secret" => {"value", :PRIVATE}})) == :not_empty
    end

    test "can use imported guard directly" do
      empty_metadata = Metadata.new(%{})
      non_empty_metadata = Metadata.new(%{"key" => "value"})

      empty_result = if is_empty_metadata(empty_metadata), do: :empty, else: :not_empty
      non_empty_result = if is_empty_metadata(non_empty_metadata), do: :empty, else: :not_empty

      assert empty_result == :empty
      assert non_empty_result == :not_empty
    end
  end

  describe "Enumerable protocol" do
    test "Enum.reduce/3 over metadata entries" do
      metadata = Metadata.new(%{"user_id" => "123", "action" => "login"})

      result =
        Enum.reduce(metadata, [], fn {key, value}, acc ->
          [{key, value.value} | acc]
        end)

      assert Enum.sort(result) == [{"action", "login"}, {"user_id", "123"}]
    end

    test "Enum.count/1 returns number of entries" do
      metadata = Metadata.new(%{"a" => "1", "b" => "2", "c" => "3"})

      assert Enum.count(metadata) == 3
    end

    test "Enum.count/1 on empty metadata returns 0" do
      metadata = Metadata.new(%{})

      # We explicitly test count/1 here because it's a protocol function we implemented.
      # This is NOT a performance anti-pattern; we're validating the Enumerable.count/1
      # protocol callback works correctly, not just checking if metadata is empty.
      # credo:disable-for-next-line
      assert Enum.count(metadata) == 0
    end

    test "Enum.map/2 transforms metadata entries" do
      metadata = Metadata.new(%{"x" => "10", "y" => "20"})

      result =
        Enum.map(metadata, fn {key, value} ->
          {key, String.to_integer(value.value) * 2}
        end)

      assert Enum.sort(result) == [{"x", 20}, {"y", 40}]
    end

    test "Enum.filter/2 filters metadata entries" do
      metadata = Metadata.new(%{"visible" => {"yes", :PUBLIC}, "hidden" => {"no", :PRIVATE}})

      result =
        Enum.filter(metadata, fn {_key, value} ->
          value.visibility == :PUBLIC
        end)

      assert length(result) == 1
      assert {key, value} = List.first(result)
      assert key == "visible"
      assert value.visibility == :PUBLIC
    end

    test "Enum.member?/2 checks membership by key" do
      metadata = Metadata.new(%{"key" => "value"})

      assert Enum.member?(metadata, "key")
      refute Enum.member?(metadata, "nonexistent")
    end

    test "Enum.member?/2 checks membership by key-value tuple" do
      metadata = Metadata.new(%{"key" => "value"})

      assert Enum.member?(metadata, {"key", %MetadataValue{value: "value", visibility: :INTERNAL}})
      refute Enum.member?(metadata, {"key", %MetadataValue{value: "wrong", visibility: :INTERNAL}})
    end

    test "Enum.to_list/1 converts metadata to list of tuples" do
      metadata = Metadata.new(%{"a" => "1", "b" => "2"})

      result = Enum.to_list(metadata)

      assert length(result) == 2

      assert Enum.all?(result, fn {key, value} ->
               is_binary(key) and is_struct(value, MetadataValue)
             end)
    end

    test "Enum.slice/2 with range" do
      metadata = Metadata.new(%{"a" => "1", "b" => "2", "c" => "3"})

      result = Enum.slice(metadata, 1..2)

      assert length(result) == 2

      assert Enum.all?(result, fn {_key, value} ->
               is_struct(value, MetadataValue)
             end)
    end

    test "Enum.slice/3 with start and length" do
      metadata = Metadata.new(%{"a" => "1", "b" => "2", "c" => "3"})

      result = Enum.slice(metadata, 0, 2)

      assert length(result) == 2

      assert Enum.all?(result, fn {_key, value} ->
               is_struct(value, MetadataValue)
             end)
    end

    test "Enum.slice/3 on empty metadata returns empty list" do
      metadata = Metadata.new(%{})

      result = Enum.slice(metadata, 0, 5)

      assert result == []
    end

    test "Enum.slice/3 with out of bounds indices" do
      metadata = Metadata.new(%{"a" => "1", "b" => "2"})

      result = Enum.slice(metadata, 5, 10)

      assert result == []
    end
  end
end
