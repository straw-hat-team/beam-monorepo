defmodule Trogon.Commanded.ObjectIdTest do
  use ExUnit.Case

  alias TestSupport

  @test_uuid "test-value-1"
  @test_uuid_2 "test-value-2"

  describe "object_type/0" do
    test "returns the configured type" do
      assert TestSupport.UserId.object_type() == "user"
      assert TestSupport.OrderId.object_type() == "order"
      assert TestSupport.AccountId.object_type() == "account"
    end

    test "returns type even when it contains the separator character" do
      assert TestSupport.TypeWithSeparatorId.object_type() == "my_user"
    end
  end

  describe "prefix/0" do
    test "returns the full prefix (type + separator)" do
      assert TestSupport.UserId.prefix() == "user_"
      assert TestSupport.OrderId.prefix() == "order_"
    end

    test "returns prefix with custom separator" do
      assert TestSupport.CustomSeparatorId.prefix() == "custom#"
    end

    test "returns prefix when type contains the separator character" do
      assert TestSupport.TypeWithSeparatorId.prefix() == "my_user_"
    end
  end

  describe "new/1" do
    test "returns {:ok, struct} for valid value" do
      assert {:ok, %TestSupport.UserId{id: @test_uuid}} = TestSupport.UserId.new(@test_uuid)
    end

    test "returns {:error, :empty_value} for empty string" do
      assert {:error, :empty_value} = TestSupport.UserId.new("")
    end

    test "returns {:ok, struct} with distinct struct types" do
      assert {:ok, user_id} = TestSupport.UserId.new(@test_uuid)
      assert {:ok, order_id} = TestSupport.OrderId.new(@test_uuid)

      assert is_struct(user_id, TestSupport.UserId)
      assert is_struct(order_id, TestSupport.OrderId)
      assert not is_struct(user_id, TestSupport.OrderId)
    end

    test "validates value when validate: :uuid is configured" do
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, %TestSupport.UuidFormatId{id: ^valid_uuid}} = TestSupport.UuidFormatId.new(valid_uuid)
      assert {:error, :invalid_uuid} = TestSupport.UuidFormatId.new("not-a-uuid")
    end

    test "validates value when validate: :integer is configured" do
      assert {:ok, %TestSupport.IntegerFormatId{id: "12345"}} = TestSupport.IntegerFormatId.new("12345")
      assert {:error, :invalid_integer} = TestSupport.IntegerFormatId.new("abc")
    end

    test "validates value with custom validator" do
      assert {:ok, %TestSupport.CustomFormatId{id: "valid-123"}} = TestSupport.CustomFormatId.new("valid-123")
      assert {:error, :invalid_custom_format} = TestSupport.CustomFormatId.new("invalid-value")
    end

    test "skips validation when no validate option" do
      assert {:ok, %TestSupport.UserId{id: "anything-goes"}} = TestSupport.UserId.new("anything-goes")
    end
  end

  describe "new!/1" do
    test "returns struct for valid value" do
      assert %TestSupport.UserId{id: @test_uuid} = TestSupport.UserId.new!(@test_uuid)
    end

    test "raises ValidationError for empty string" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/empty_value/, fn ->
        TestSupport.UserId.new!("")
      end
    end

    test "raises ValidationError when validation fails" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_uuid/, fn ->
        TestSupport.UuidFormatId.new!("not-a-uuid")
      end
    end

    test "returns struct when validation passes" do
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert %TestSupport.UuidFormatId{id: ^valid_uuid} = TestSupport.UuidFormatId.new!(valid_uuid)
    end
  end

  describe "parse/1" do
    test "parses a valid string" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      typeid_string = to_string(typeid)

      assert {:ok, parsed} = TestSupport.UserId.parse(typeid_string)
      assert parsed.id == typeid.id
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = TestSupport.UserId.parse("invalid")
    end

    test "returns error for wrong prefix" do
      order_string = to_string(TestSupport.OrderId.new!(@test_uuid))
      assert {:error, :invalid_format} = TestSupport.UserId.parse(order_string)
    end

    test "raises FunctionClauseError for non-binary input" do
      assert_raise FunctionClauseError, fn ->
        TestSupport.UserId.parse(123)
      end
    end

    test "parses when type contains the separator character" do
      typeid = TestSupport.TypeWithSeparatorId.new!("test-123")
      {:ok, dumped} = TestSupport.TypeWithSeparatorId.dump(typeid)

      {:ok, parsed} = TestSupport.TypeWithSeparatorId.parse(dumped)
      assert parsed.id == "test-123"
    end

    test "parses with custom separator" do
      typeid = TestSupport.CustomSeparatorId.new!(@test_uuid)
      string = to_string(typeid)

      {:ok, parsed} = TestSupport.CustomSeparatorId.parse(string)
      assert parsed.id == typeid.id
    end

    test "returns error when parsing with wrong separator" do
      wrong_string = "custom_test"
      assert {:error, :invalid_format} = TestSupport.CustomSeparatorId.parse(wrong_string)
    end

    test "round-trips: new! -> to_string -> parse" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      typeid_string = to_string(typeid)

      {:ok, parsed} = TestSupport.UserId.parse(typeid_string)
      assert parsed.id == typeid.id
    end
  end

  describe "parse!/1" do
    test "parses a valid string" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      typeid_string = to_string(typeid)

      parsed = TestSupport.UserId.parse!(typeid_string)
      assert parsed.id == typeid.id
    end

    test "raises Error for invalid format" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_format/, fn ->
        TestSupport.UserId.parse!("invalid")
      end
    end

    test "raises Error for wrong prefix" do
      order_string = to_string(TestSupport.OrderId.new!(@test_uuid))

      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_format/, fn ->
        TestSupport.UserId.parse!(order_string)
      end
    end

    test "error includes the invalid value" do
      invalid_value = "some_bad_value_123"

      error =
        assert_raise Trogon.Commanded.ObjectId.ValidationError, fn ->
          TestSupport.UserId.parse!(invalid_value)
        end

      assert error.value == invalid_value
    end

    test "parses with custom separator" do
      typeid = TestSupport.CustomSeparatorId.new!(@test_uuid)
      string = to_string(typeid)

      parsed = TestSupport.CustomSeparatorId.parse!(string)
      assert parsed.id == typeid.id
    end
  end

  describe "type/0" do
    test "returns :string" do
      assert TestSupport.UserId.type() == :string
    end
  end

  describe "cast/1" do
    test "accepts the struct" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      assert {:ok, ^typeid} = TestSupport.UserId.cast(typeid)
    end

    test "accepts binary strings" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      typeid_string = to_string(typeid)

      assert {:ok, parsed} = TestSupport.UserId.cast(typeid_string)
      assert parsed.id == typeid.id
    end

    test "returns error for invalid string" do
      assert {:error, :invalid_format} = TestSupport.UserId.cast("invalid")
    end

    test "returns error for non-binary input" do
      assert :error = TestSupport.UserId.cast(123)
    end

    test "returns error for struct with nil id" do
      assert :error = TestSupport.UserId.cast(%TestSupport.UserId{id: nil})
    end

    test "returns {:ok, nil} for nil (nullable fields)" do
      assert {:ok, nil} = TestSupport.UserId.cast(nil)
    end

    test "converts empty string to nil (form input pattern)" do
      assert {:ok, nil} = TestSupport.UserId.cast("")
    end

    test "rejects prefix with empty suffix" do
      assert {:error, :invalid_format} = TestSupport.UserId.cast("user_")
    end

    test "rejects struct with empty id" do
      assert :error = TestSupport.UserId.cast(%TestSupport.UserId{id: ""})
    end

    test "rejects struct with empty id (consistent with cast)" do
      assert :error = TestSupport.UserId.cast(%TestSupport.UserId{id: ""})
    end
  end

  describe "load/1" do
    test "loads with storage_format: :full (default)" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      typeid_string = to_string(typeid)

      assert {:ok, loaded} = TestSupport.UserId.load(typeid_string)
      assert loaded.id == typeid.id
    end

    test "loads with storage_format: :full" do
      dumped = "full_#{@test_uuid}"
      assert {:ok, loaded} = TestSupport.FullStorageId.load(dumped)
      assert loaded.id == @test_uuid
    end

    test "loads with storage_format: :drop_prefix by reconstructing prefix" do
      assert {:ok, loaded} = TestSupport.DropPrefixId.load(@test_uuid)
      assert loaded.id == @test_uuid
    end

    test "returns error for invalid input" do
      assert :error = TestSupport.UserId.load("invalid")
    end

    test "returns {:ok, nil} for nil (NULL from database)" do
      assert {:ok, nil} = TestSupport.UserId.load(nil)
    end

    test "converts empty string to nil when loading" do
      assert {:ok, nil} = TestSupport.UserId.load("")
    end
  end

  describe "to_storage/1" do
    test "converts valid struct to storage format (default :full)" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      assert TestSupport.UserId.to_storage(typeid) == "user_#{@test_uuid}"
    end

    test "converts valid struct to storage format (:drop_prefix)" do
      typeid = TestSupport.DropPrefixId.new!(@test_uuid)

      assert TestSupport.DropPrefixId.to_storage(typeid) == @test_uuid
    end

    test "converts valid struct with custom separator" do
      typeid = TestSupport.CustomSeparatorId.new!(@test_uuid)

      assert TestSupport.CustomSeparatorId.to_storage(typeid) == "custom##{@test_uuid}"
    end
  end

  describe "dump/1" do
    test "dumps with storage_format: :full (default)" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      assert {:ok, dumped} = TestSupport.UserId.dump(typeid)
      assert dumped == "user_#{@test_uuid}"
    end

    test "dumps with storage_format: :full" do
      typeid = TestSupport.FullStorageId.new!(@test_uuid)

      assert {:ok, dumped} = TestSupport.FullStorageId.dump(typeid)
      assert dumped == "full_#{@test_uuid}"
    end

    test "dumps with storage_format: :drop_prefix (only id)" do
      typeid = TestSupport.DropPrefixId.new!(@test_uuid)

      assert {:ok, dumped} = TestSupport.DropPrefixId.dump(typeid)
      assert dumped == @test_uuid
    end

    test "dumps when type contains the separator character" do
      typeid = TestSupport.TypeWithSeparatorId.new!("test-123")

      {:ok, dumped} = TestSupport.TypeWithSeparatorId.dump(typeid)
      assert dumped == "my_user_test-123"
    end

    test "returns error for invalid input" do
      assert :error = TestSupport.UserId.dump("invalid")
    end

    test "returns error for struct with nil id" do
      assert :error = TestSupport.UserId.dump(%TestSupport.UserId{id: nil})
    end

    test "returns error for struct with empty id" do
      assert :error = TestSupport.UserId.dump(%TestSupport.UserId{id: ""})
    end

    test "returns {:ok, nil} for nil (store NULL in database)" do
      assert {:ok, nil} = TestSupport.UserId.dump(nil)
    end

    test "delegates to to_storage for valid struct" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      {:ok, dump_result} = TestSupport.UserId.dump(typeid)
      storage_result = TestSupport.UserId.to_storage(typeid)

      assert dump_result == storage_result
    end

    test "enforces struct pattern matching before calling to_storage" do
      assert :error = TestSupport.UserId.dump(%{id: @test_uuid})
      assert :error = TestSupport.UserId.dump(%{"id" => @test_uuid})
      assert :error = TestSupport.UserId.dump(123)
    end
  end

  describe "equal?/2" do
    test "returns true for same id" do
      uuid1 = TestSupport.UserId.new!(@test_uuid)
      uuid1_dup = %TestSupport.UserId{id: uuid1.id}

      assert TestSupport.UserId.equal?(uuid1, uuid1_dup)
    end

    test "returns false for different ids" do
      uuid1 = TestSupport.UserId.new!(@test_uuid)
      uuid2 = TestSupport.UserId.new!(@test_uuid_2)

      assert not TestSupport.UserId.equal?(uuid1, uuid2)
    end

    test "returns false for invalid input" do
      uuid1 = TestSupport.UserId.new!(@test_uuid)

      assert not TestSupport.UserId.equal?(uuid1, "invalid")
    end
  end

  describe "embed_as/1" do
    test "returns :self" do
      assert TestSupport.UserId.embed_as(:json) == :self
    end
  end

  describe "String.Chars.to_string/1" do
    test "converts to string with prefix" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      assert to_string(typeid) == "user_#{@test_uuid}"
    end

    test "works in string interpolation" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      assert "User ID: #{typeid}" == "User ID: user_#{@test_uuid}"
    end

    test "uses custom separator" do
      typeid = TestSupport.CustomSeparatorId.new!(@test_uuid)

      assert to_string(typeid) == "custom##{@test_uuid}"
    end

    test "different types produce different strings" do
      user_id = TestSupport.UserId.new!(@test_uuid)
      order_id = TestSupport.OrderId.new!(@test_uuid)

      assert to_string(user_id) == "user_#{@test_uuid}"
      assert to_string(order_id) == "order_#{@test_uuid}"
    end
  end

  describe "Jason.Encoder.encode/2" do
    test "protocol is implemented when Jason is available" do
      assert {:ok, _} = Jason.encode(%TestSupport.UserId{id: "test"})
      assert {:ok, _} = Jason.encode(%TestSupport.DropPrefixId{id: "test"})
    end

    test "encodes with json_format: :full (default)" do
      typeid = TestSupport.UserId.new!(@test_uuid)

      assert Jason.encode!(typeid) == ~s("user_#{@test_uuid}")
    end

    test "encodes with json_format: :drop_prefix" do
      typeid = TestSupport.JsonDropPrefixId.new!(@test_uuid)

      assert Jason.encode!(typeid) == ~s("#{@test_uuid}")
    end

    test "encodes with custom separator" do
      typeid = TestSupport.CustomSeparatorId.new!(@test_uuid)

      assert Jason.encode!(typeid) == ~s("custom##{@test_uuid}")
    end

    test "json_format is independent from storage_format" do
      mixed_id = TestSupport.StorageDropJsonFullId.new!(@test_uuid)
      assert {:ok, dumped} = TestSupport.StorageDropJsonFullId.dump(mixed_id)
      assert dumped == @test_uuid
      assert Jason.encode!(mixed_id) == ~s("mixed_#{@test_uuid}")

      json_drop_id = TestSupport.JsonDropPrefixId.new!(@test_uuid)
      assert {:ok, dumped} = TestSupport.JsonDropPrefixId.dump(json_drop_id)
      assert dumped == "jsondrop_#{@test_uuid}"
      assert Jason.encode!(json_drop_id) == ~s("#{@test_uuid}")
    end

    test "encodes within a map" do
      typeid = TestSupport.UserId.new!(@test_uuid)
      map = %{id: typeid, name: "test"}

      assert Jason.encode!(map) == ~s({"id":"user_#{@test_uuid}","name":"test"})
    end

    test "encodes within a list" do
      typeid1 = TestSupport.UserId.new!("id1")
      typeid2 = TestSupport.UserId.new!("id2")

      assert Jason.encode!([typeid1, typeid2]) == ~s(["user_id1","user_id2"])
    end

    test "raises FunctionClauseError for struct with nil id" do
      assert_raise FunctionClauseError, fn ->
        Jason.encode!(%TestSupport.UserId{id: nil})
      end
    end

    test "encodes struct with empty string id (edge case from direct construction)" do
      assert Jason.encode!(%TestSupport.UserId{id: ""}) == ~s("user_")
    end
  end

  describe "format validation: :uuid" do
    @valid_uuid "550e8400-e29b-41d4-a716-446655440000"

    test "accepts valid UUID" do
      result = TestSupport.UuidFormatId.parse("uuid_#{@valid_uuid}")

      assert {:ok, %TestSupport.UuidFormatId{id: @valid_uuid}} = result
    end

    test "rejects invalid UUID" do
      assert {:error, :invalid_uuid} = TestSupport.UuidFormatId.parse("uuid_not-a-uuid")
    end

    test "rejects empty UUID" do
      assert {:error, :invalid_format} = TestSupport.UuidFormatId.parse("uuid_")
    end

    test "works with storage_format: :drop_prefix" do
      result = TestSupport.UuidDropPrefixId.parse("uuiddrop_#{@valid_uuid}")

      assert {:ok, %TestSupport.UuidDropPrefixId{id: @valid_uuid}} = result
    end

    test "validates the raw id value regardless of storage_format" do
      assert {:error, :invalid_uuid} = TestSupport.UuidDropPrefixId.parse("uuiddrop_invalid")
    end

    test "parse! raises Error for invalid UUID" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_uuid/, fn ->
        TestSupport.UuidFormatId.parse!("uuid_not-a-uuid")
      end
    end

    test "cast delegates to parse and validates UUID" do
      assert {:ok, %TestSupport.UuidFormatId{}} =
               TestSupport.UuidFormatId.cast("uuid_#{@valid_uuid}")

      assert {:error, :invalid_uuid} = TestSupport.UuidFormatId.cast("uuid_invalid")
    end
  end

  describe "format validation: :integer" do
    test "accepts valid integer string" do
      assert {:ok, %TestSupport.IntegerFormatId{id: "12345"}} =
               TestSupport.IntegerFormatId.parse("int_12345")
    end

    test "accepts zero" do
      assert {:ok, %TestSupport.IntegerFormatId{id: "0"}} =
               TestSupport.IntegerFormatId.parse("int_0")
    end

    test "accepts negative integers" do
      assert {:ok, %TestSupport.IntegerFormatId{id: "-123"}} =
               TestSupport.IntegerFormatId.parse("int_-123")
    end

    test "rejects non-integer strings" do
      assert {:error, :invalid_integer} = TestSupport.IntegerFormatId.parse("int_abc")
    end

    test "rejects integers with trailing characters" do
      assert {:error, :invalid_integer} = TestSupport.IntegerFormatId.parse("int_123abc")
    end

    test "rejects floats" do
      assert {:error, :invalid_integer} = TestSupport.IntegerFormatId.parse("int_12.34")
    end

    test "parse! raises Error for invalid integer" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_integer/, fn ->
        TestSupport.IntegerFormatId.parse!("int_not-an-int")
      end
    end
  end

  describe "format validation: custom function" do
    test "accepts values passing custom validation" do
      assert {:ok, %TestSupport.CustomFormatId{id: "valid-123"}} =
               TestSupport.CustomFormatId.parse("custom_fmt_valid-123")
    end

    test "rejects values failing custom validation" do
      assert {:error, :invalid_custom_format} =
               TestSupport.CustomFormatId.parse("custom_fmt_invalid-value")
    end

    test "parse! raises Error for invalid custom format" do
      assert_raise Trogon.Commanded.ObjectId.ValidationError, ~r/invalid_custom_format/, fn ->
        TestSupport.CustomFormatId.parse!("custom_fmt_bad")
      end
    end
  end

  describe "format validation: no format specified" do
    test "ObjectId without format accepts any value" do
      assert {:ok, %TestSupport.UserId{id: "any-value-here"}} =
               TestSupport.UserId.parse("user_any-value-here")
    end
  end

  describe "format validation: compile-time errors" do
    test "raises ArgumentError when function does not exist" do
      assert_raise ArgumentError, ~r/String.nonexistent\/1 is not defined/, fn ->
        Code.compile_string("""
        defmodule TestNonexistentFunc do
          use Trogon.Commanded.ObjectId, object_type: "test", validate: {String, :nonexistent}
        end
        """)
      end
    end

    test "raises NimbleOptions.ValidationError for invalid validate type" do
      assert_raise NimbleOptions.ValidationError, fn ->
        Code.compile_string("""
        defmodule TestInvalidValidate do
          use Trogon.Commanded.ObjectId, object_type: "test", validate: :invalid
        end
        """)
      end
    end
  end

  describe "proto: option" do
    test "derives object_type from proto enum value" do
      assert TestSupport.ProtoTicketId.object_type() == "ticket"
    end

    test "uses default separator when proto does not specify one" do
      assert TestSupport.ProtoTicketId.prefix() == "ticket_"
    end

    test "derives custom separator from proto enum value" do
      assert TestSupport.ProtoWorkspaceId.object_type() == "workspace"
      assert TestSupport.ProtoWorkspaceId.prefix() == "workspace#"
    end

    test "forwards additional options like storage_format" do
      typeid = TestSupport.ProtoWorkspaceId.new!("abc-123")
      assert {:ok, dumped} = TestSupport.ProtoWorkspaceId.dump(typeid)
      assert dumped == "abc-123"
    end

    test "round-trips: new! -> to_string -> parse" do
      typeid = TestSupport.ProtoTicketId.new!("abc-123")
      assert to_string(typeid) == "ticket_abc-123"
      assert {:ok, parsed} = TestSupport.ProtoTicketId.parse("ticket_abc-123")
      assert parsed.id == "abc-123"
    end
  end
end
