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
      assert entries["key"] == %MetadataValue{value: "value", visibility: :internal}
    end

    test "creates metadata with tuple format" do
      metadata = Metadata.new(%{"secret" => {"api-key", :private}})
      assert %Metadata{entries: entries} = metadata
      assert entries["secret"] == %MetadataValue{value: "api-key", visibility: :private}
    end

    test "creates metadata with MetadataValue structs" do
      value = MetadataValue.new("test", :public)
      metadata = Metadata.new(%{"existing" => value})
      assert %Metadata{entries: entries} = metadata
      assert entries["existing"] == value
    end

    test "converts atom keys to strings" do
      metadata = Metadata.new(%{user_id: "123"})
      assert %Metadata{entries: entries} = metadata
      assert entries["user_id"] == %MetadataValue{value: "123", visibility: :internal}
    end

    test "handles mixed value types" do
      metadata =
        Metadata.new(%{
          "simple" => "value",
          "tuple" => {"secret", :private},
          "struct" => MetadataValue.new("existing", :public),
          atom_key: 42
        })

      assert %Metadata{entries: entries} = metadata
      assert entries["simple"] == %MetadataValue{value: "value", visibility: :internal}
      assert entries["tuple"] == %MetadataValue{value: "secret", visibility: :private}
      assert entries["struct"] == %MetadataValue{value: "existing", visibility: :public}
      assert entries["atom_key"] == %MetadataValue{value: "42", visibility: :internal}
    end
  end

  describe "merge/2" do
    test "merges two metadata structs" do
      metadata1 = Metadata.new(%{"key1" => "value1"})
      metadata2 = Metadata.new(%{"key2" => "value2"})

      merged = Metadata.merge(metadata1, metadata2)

      assert %Metadata{entries: entries} = merged
      assert entries["key1"] == %MetadataValue{value: "value1", visibility: :internal}
      assert entries["key2"] == %MetadataValue{value: "value2", visibility: :internal}
    end

    test "second metadata overwrites first on key conflicts" do
      metadata1 = Metadata.new(%{"key" => "value1"})
      metadata2 = Metadata.new(%{"key" => "value2"})

      merged = Metadata.merge(metadata1, metadata2)

      assert %Metadata{entries: entries} = merged
      assert entries["key"] == %MetadataValue{value: "value2", visibility: :internal}
    end
  end

  describe "Access behavior" do
    setup do
      metadata =
        Metadata.new(%{
          "public" => {"visible", :public},
          "private" => {"hidden", :private},
          "internal" => "default"
        })

      {:ok, metadata: metadata}
    end

    test "fetch/2 returns metadata values", %{metadata: metadata} do
      assert {:ok, value} = Metadata.fetch(metadata, "public")
      assert value == %MetadataValue{value: "visible", visibility: :public}

      assert :error = Metadata.fetch(metadata, "nonexistent")
    end

    test "supports bracket access", %{metadata: metadata} do
      assert metadata["public"] == %MetadataValue{value: "visible", visibility: :public}
      assert metadata["private"] == %MetadataValue{value: "hidden", visibility: :private}
      assert metadata["internal"] == %MetadataValue{value: "default", visibility: :internal}
      assert metadata["nonexistent"] == nil
    end

    test "supports get_and_update/3", %{metadata: metadata} do
      {old_value, new_metadata} =
        Metadata.get_and_update(metadata, "public", fn value ->
          {value, %{value | visibility: :internal}}
        end)

      assert old_value == %MetadataValue{value: "visible", visibility: :public}
      assert new_metadata["public"] == %MetadataValue{value: "visible", visibility: :internal}
    end

    test "supports pop/2", %{metadata: metadata} do
      {popped_value, new_metadata} = Metadata.pop(metadata, "private")

      assert popped_value == %MetadataValue{value: "hidden", visibility: :private}
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
      assert MetadataTestGuards.test_empty(Metadata.new(%{"secret" => {"value", :private}})) == :not_empty
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
end
