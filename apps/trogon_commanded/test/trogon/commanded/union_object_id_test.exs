defmodule Trogon.Commanded.UnionObjectIdTest do
  use ExUnit.Case

  alias TestSupport

  @tenant_id_value "abc-123"
  @system_id_value "xyz-789"
  @service_id_value "srv-456"

  describe "new/1" do
    test "wraps a TenantId" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.PrincipalId.new(tenant_id)

      assert union == %TestSupport.PrincipalId{id: tenant_id}
    end

    test "wraps a SystemId" do
      system_id = TestSupport.SystemId.new(@system_id_value)
      union = TestSupport.ContextId.new(system_id)

      assert union == %TestSupport.ContextId{id: system_id}
    end

    test "supports unions with more than two types" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      system_id = TestSupport.SystemId.new(@system_id_value)
      service_id = TestSupport.ServiceId.new(@service_id_value)

      assert TestSupport.PrincipalId.new(tenant_id) == %TestSupport.PrincipalId{id: tenant_id}
      assert TestSupport.PrincipalId.new(system_id) == %TestSupport.PrincipalId{id: system_id}
      assert TestSupport.PrincipalId.new(service_id) == %TestSupport.PrincipalId{id: service_id}
    end

    test "distinguishes between different unions" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      mod_union = TestSupport.ContextId.new(tenant_id)
      actor_union = TestSupport.PrincipalId.new(tenant_id)

      assert mod_union == %TestSupport.ContextId{id: tenant_id}
      assert actor_union == %TestSupport.PrincipalId{id: tenant_id}
    end
  end

  describe "parse/1" do
    test "parses a TenantId string" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.ContextId.parse(tenant_string)
    end

    test "parses a SystemId string" do
      system_string = to_string(TestSupport.SystemId.new(@system_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.SystemId{id: @system_id_value}}} =
               TestSupport.ContextId.parse(system_string)
    end

    test "tries each type in order and returns first match" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{}}} = TestSupport.ContextId.parse(tenant_string)
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = TestSupport.ContextId.parse("")
    end

    test "returns error for invalid string" do
      assert {:error, :invalid_format} = TestSupport.ContextId.parse("invalid")
    end

    test "returns error when string doesn't match any type" do
      assert {:error, :invalid_format} = TestSupport.ContextId.parse("unknown_abc-123")
    end

    test "handles three-type unions" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))
      system_string = to_string(TestSupport.SystemId.new(@system_id_value))
      service_string = to_string(TestSupport.ServiceId.new(@service_id_value))

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.PrincipalId.parse(tenant_string)

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.SystemId{id: @system_id_value}}} =
               TestSupport.PrincipalId.parse(system_string)

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.ServiceId{id: @service_id_value}}} =
               TestSupport.PrincipalId.parse(service_string)
    end
  end

  describe "to_storage/1" do
    test "converts TenantId to storage string with prefix" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      assert TestSupport.ContextId.to_storage(union) == "tenant_#{@tenant_id_value}"
    end

    test "converts SystemId to storage string with prefix" do
      system_id = TestSupport.SystemId.new(@system_id_value)
      union = TestSupport.ContextId.new(system_id)

      assert TestSupport.ContextId.to_storage(union) == "system_#{@system_id_value}"
    end

    test "storage string is the same as to_string output" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      assert TestSupport.ContextId.to_storage(union) == to_string(union)
    end

    test "raises FunctionClauseError when id is nil" do
      assert_raise FunctionClauseError, fn ->
        TestSupport.ContextId.to_storage(%TestSupport.ContextId{id: nil})
      end
    end

    test "raises FunctionClauseError when id is not a struct" do
      assert_raise FunctionClauseError, fn ->
        TestSupport.ContextId.to_storage(%TestSupport.ContextId{id: "string"})
      end
    end
  end

  describe "String.Chars protocol" do
    test "converts TenantId to string with prefix" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      assert to_string(union) == "tenant_#{@tenant_id_value}"
    end

    test "converts SystemId to string with prefix" do
      system_id = TestSupport.SystemId.new(@system_id_value)
      union = TestSupport.ContextId.new(system_id)

      assert to_string(union) == "system_#{@system_id_value}"
    end

    test "can be used in string interpolation" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      result = "Context: #{union}"

      assert result == "Context: tenant_#{@tenant_id_value}"
    end
  end

  describe "cast/1" do
    test "casts nil" do
      assert {:ok, nil} = TestSupport.ContextId.cast(nil)
    end

    test "casts empty string to nil" do
      assert {:ok, nil} = TestSupport.ContextId.cast("")
    end

    test "casts a union struct" do
      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.ContextId.cast(%TestSupport.ContextId{id: TestSupport.TenantId.new(@tenant_id_value)})
    end

    test "casts a valid string to TenantId" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.ContextId.cast(tenant_string)
    end

    test "casts a valid string to SystemId" do
      system_string = to_string(TestSupport.SystemId.new(@system_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.SystemId{id: @system_id_value}}} =
               TestSupport.ContextId.cast(system_string)
    end

    test "returns error for invalid string" do
      assert :error = TestSupport.ContextId.cast("invalid")
    end

    test "returns error for non-string non-struct input" do
      assert :error = TestSupport.ContextId.cast(123)
      assert :error = TestSupport.ContextId.cast([])
      assert :error = TestSupport.ContextId.cast(%{})
    end
  end

  describe "load/1" do
    test "loads nil" do
      assert {:ok, nil} = TestSupport.ContextId.load(nil)
    end

    test "loads empty string as nil" do
      assert {:ok, nil} = TestSupport.ContextId.load("")
    end

    test "loads a valid TenantId string" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.ContextId.load(tenant_string)
    end

    test "loads a valid SystemId string" do
      system_string = to_string(TestSupport.SystemId.new(@system_id_value))

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.SystemId{id: @system_id_value}}} =
               TestSupport.ContextId.load(system_string)
    end

    test "returns error for invalid string" do
      assert :error = TestSupport.ContextId.load("invalid")
    end

    test "returns error for non-string input" do
      assert :error = TestSupport.ContextId.load(123)
      assert :error = TestSupport.ContextId.load([])
    end
  end

  describe "dump/1" do
    test "dumps nil" do
      assert {:ok, nil} = TestSupport.ContextId.dump(nil)
    end

    test "dumps a union with TenantId" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      assert {:ok, "tenant_#{@tenant_id_value}"} = TestSupport.ContextId.dump(union)
    end

    test "dumps a union with SystemId" do
      system_id = TestSupport.SystemId.new(@system_id_value)
      union = TestSupport.ContextId.new(system_id)

      assert {:ok, "system_#{@system_id_value}"} = TestSupport.ContextId.dump(union)
    end

    test "returns error for non-union struct" do
      assert :error = TestSupport.ContextId.dump(123)
      assert :error = TestSupport.ContextId.dump("string")
      assert :error = TestSupport.ContextId.dump(%{})
    end

    test "returns error when id is nil" do
      assert :error = TestSupport.ContextId.dump(%TestSupport.ContextId{id: nil})
    end

    test "returns error when id is not a struct" do
      assert :error = TestSupport.ContextId.dump(%TestSupport.ContextId{id: "string"})
    end
  end

  describe "type/0" do
    test "returns :string" do
      assert TestSupport.ContextId.type() == :string
    end
  end

  describe "equal?/2" do
    test "returns true for equal unions with TenantId" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union1 = TestSupport.ContextId.new(tenant_id)
      union2 = TestSupport.ContextId.new(tenant_id)

      assert TestSupport.ContextId.equal?(union1, union2)
    end

    test "returns false for unions with different inner values" do
      tenant_id1 = TestSupport.TenantId.new(@tenant_id_value)
      tenant_id2 = TestSupport.TenantId.new("different")
      union1 = TestSupport.ContextId.new(tenant_id1)
      union2 = TestSupport.ContextId.new(tenant_id2)

      assert not TestSupport.ContextId.equal?(union1, union2)
    end

    test "returns false for unions with different inner types" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      system_id = TestSupport.SystemId.new(@tenant_id_value)
      tenant_union = TestSupport.ContextId.new(tenant_id)
      system_union = TestSupport.ContextId.new(system_id)

      assert not TestSupport.ContextId.equal?(tenant_union, system_union)
    end

    test "returns false when comparing with non-union" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      assert not TestSupport.ContextId.equal?(union, nil)
      assert not TestSupport.ContextId.equal?(union, "string")
    end
  end

  describe "embed_as/1" do
    test "returns :self" do
      assert TestSupport.ContextId.embed_as(:atom) == :self
      assert TestSupport.ContextId.embed_as(:json) == :self
    end
  end

  describe "Jason.Encoder protocol" do
    test "encodes TenantId union to JSON" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      json = Jason.encode!(union)

      assert json == Jason.encode!("tenant_#{@tenant_id_value}")
    end

    test "encodes SystemId union to JSON" do
      system_id = TestSupport.SystemId.new(@system_id_value)
      union = TestSupport.ContextId.new(system_id)

      json = Jason.encode!(union)

      assert json == Jason.encode!("system_#{@system_id_value}")
    end

    test "decodes JSON to union via cast" do
      tenant_id = TestSupport.TenantId.new(@tenant_id_value)
      union = TestSupport.ContextId.new(tenant_id)

      json = Jason.encode!(union)
      decoded = Jason.decode!(json)

      assert {:ok, %TestSupport.ContextId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.ContextId.cast(decoded)
    end
  end

  describe "Prefix collision detection at compile time" do
    test "raises CompileError for overlapping prefixes" do
      assert_raise CompileError, ~r/UnionObjectId prefix collision/, fn ->
        Code.compile_string("""
        defmodule TestSupport.BadUnionId do
          use Trogon.Commanded.UnionObjectId, types: [TestSupport.TenantId, TestSupport.TenantId]
        end
        """)
      end
    end

    test "raises CompileError for empty types list" do
      assert_raise CompileError, ~r/types list cannot be empty/, fn ->
        Code.compile_string("""
        defmodule TestSupport.EmptyUnionId do
          use Trogon.Commanded.UnionObjectId, types: []
        end
        """)
      end
    end

    test "raises CompileError for ambiguous prefixes with different separators" do
      assert_raise CompileError, ~r/UnionObjectId prefix collision/, fn ->
        Code.compile_string("""
        defmodule TestSupport.AmbiguousUnionId do
          use Trogon.Commanded.UnionObjectId,
            types: [TestSupport.AmbiguousPrefixIdA, TestSupport.AmbiguousPrefixIdB]
        end
        """)
      end
    end
  end

  describe "Union with multiple types" do
    test "correctly identifies TenantId variant" do
      tenant_string = to_string(TestSupport.TenantId.new(@tenant_id_value))

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.TenantId{id: @tenant_id_value}}} =
               TestSupport.PrincipalId.parse(tenant_string)
    end

    test "correctly identifies SystemId variant" do
      system_string = to_string(TestSupport.SystemId.new(@system_id_value))

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.SystemId{id: @system_id_value}}} =
               TestSupport.PrincipalId.parse(system_string)
    end

    test "correctly identifies ServiceId variant" do
      service_string = to_string(TestSupport.ServiceId.new(@service_id_value))

      assert {:ok, %TestSupport.PrincipalId{id: %TestSupport.ServiceId{id: @service_id_value}}} =
               TestSupport.PrincipalId.parse(service_string)
    end
  end
end
