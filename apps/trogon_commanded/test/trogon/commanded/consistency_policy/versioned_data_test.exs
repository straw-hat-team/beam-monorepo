defmodule Trogon.Commanded.ConsistencyPolicy.VersionedDataTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.ConsistencyPolicy.VersionedData

  describe "new/2" do
    test "creates versioned data" do
      data = VersionedData.new(5, %{id: "123"})
      assert data.version == 5
      assert data.data == %{id: "123"}
    end

    test "accepts version 0" do
      data = VersionedData.new(0, :anything)
      assert data.version == 0
      assert data.data == :anything
    end

    test "accepts any term as data" do
      assert VersionedData.new(1, nil).data == nil
      assert VersionedData.new(1, [1, 2, 3]).data == [1, 2, 3]
      assert VersionedData.new(1, "string").data == "string"
    end

    test "raises on negative version" do
      assert_raise FunctionClauseError, fn ->
        VersionedData.new(-1, %{})
      end
    end

    test "raises on non-integer version" do
      assert_raise FunctionClauseError, fn ->
        VersionedData.new("5", %{})
      end
    end

    test "raises on float version" do
      assert_raise FunctionClauseError, fn ->
        VersionedData.new(5.0, %{})
      end
    end
  end
end
