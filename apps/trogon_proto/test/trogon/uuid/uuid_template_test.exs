defmodule Trogon.Proto.Uuid.V1.UuidTemplateTest do
  use ExUnit.Case, async: true

  # Generated proto modules from test/proto/*.proto
  alias Acme.FileNamespace.V1.FileNamespaceId
  alias Acme.Order.V1.OrderId
  alias Invalid.NoFormat.V1.NoFormatId

  # Test support modules using UuidTemplate
  alias Trogon.Proto.TestSupport.AcmeOrderId
  alias Trogon.Proto.TestSupport.StaticSingletonId
  alias Trogon.Proto.TestSupport.DnsNamespaceId
  alias Trogon.Proto.TestSupport.UrlNamespaceId
  alias Trogon.Proto.TestSupport.UuidNamespaceId
  alias Trogon.Proto.TestSupport.ValueNamespaceV1Id
  alias Trogon.Proto.TestSupport.ValueNamespaceV2Id

  alias Trogon.Proto.Uuid.V1.UuidTemplate

  describe "uuid5/1 with dynamic template" do
    test "generates deterministic UUID for order" do
      uuid =
        AcmeOrderId.uuid5(%{
          customer_id: "cust-123",
          order_number: "ORD-456"
        })

      assert is_binary(uuid)
      assert byte_size(uuid) == 36
    end

    test "generates same UUID for same inputs" do
      values = %{customer_id: "c1", order_number: "o1"}

      uuid1 = AcmeOrderId.uuid5(values)
      uuid2 = AcmeOrderId.uuid5(values)

      assert uuid1 == uuid2
    end

    test "generates different UUIDs for different inputs" do
      uuid1 = AcmeOrderId.uuid5(%{customer_id: "c1", order_number: "o1"})
      uuid2 = AcmeOrderId.uuid5(%{customer_id: "c2", order_number: "o1"})

      assert uuid1 != uuid2
    end

    test "accepts any String.Chars.t() value (integer, atom, etc)" do
      uuid_with_strings = AcmeOrderId.uuid5(%{customer_id: "123", order_number: "456"})
      uuid_with_integers = AcmeOrderId.uuid5(%{customer_id: 123, order_number: 456})

      # Both should produce valid UUIDs
      assert byte_size(uuid_with_strings) == 36
      assert byte_size(uuid_with_integers) == 36

      # Same string representation = same UUID
      assert uuid_with_strings == uuid_with_integers
    end

    test "raises KeyError when required key is missing" do
      assert_raise KeyError, fn ->
        AcmeOrderId.uuid5(%{customer_id: "c1"})
      end
    end

    test "generated UUID matches UUIDv5 format" do
      uuid = AcmeOrderId.uuid5(%{customer_id: "test", order_number: "123"})

      # UUIDv5 format: xxxxxxxx-xxxx-5xxx-yxxx-xxxxxxxxxxxx
      # where y is 8, 9, a, or b
      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               uuid
             )
    end
  end

  describe "uuid5/0 with static template" do
    test "generates 0-arity function for template with no placeholders" do
      uuid = StaticSingletonId.uuid5()

      assert is_binary(uuid)
      assert byte_size(uuid) == 36
    end

    test "always returns the same UUID (singleton)" do
      uuid1 = StaticSingletonId.uuid5()
      uuid2 = StaticSingletonId.uuid5()

      assert uuid1 == uuid2
    end
  end

  describe "namespace types" do
    test "works with DNS namespace" do
      uuid = DnsNamespaceId.uuid5(%{customer_id: "c1", order_number: "o1"})
      assert byte_size(uuid) == 36
    end

    test "works with URL namespace" do
      uuid = UrlNamespaceId.uuid5(%{resource_id: "res-123"})
      assert byte_size(uuid) == 36
    end

    test "works with custom UUID namespace" do
      uuid = UuidNamespaceId.uuid5(%{entity_id: "ent-456"})
      assert byte_size(uuid) == 36
    end

    test "different namespace types produce different UUIDs for same logical input" do
      dns_uuid = DnsNamespaceId.uuid5(%{customer_id: "test", order_number: "123"})
      url_uuid = UrlNamespaceId.uuid5(%{resource_id: "test"})

      assert dns_uuid != url_uuid
    end
  end

  describe "namespace resolution" do
    # Tests the namespace resolution order:
    # 1. Value-level namespace (format.namespace) - highest priority
    # 2. Enum-level namespace (enum.namespace) - fallback

    test "uses enum-level namespace when value has no override" do
      # V1 uses enum-level namespace (dns: "enum-level.acme.com")
      uuid = ValueNamespaceV1Id.uuid5(%{value_id: "test"})
      assert byte_size(uuid) == 36
    end

    test "uses value-level namespace override when specified" do
      # V2 overrides with value-level namespace (dns: "value-level.acme.com")
      uuid = ValueNamespaceV2Id.uuid5(%{value_id: "test"})
      assert byte_size(uuid) == 36
    end

    test "value-level namespace produces different UUID than enum-level for same input" do
      # Same input, but different namespaces should produce different UUIDs
      v1_uuid = ValueNamespaceV1Id.uuid5(%{value_id: "test"})
      v2_uuid = ValueNamespaceV2Id.uuid5(%{value_id: "test"})

      assert v1_uuid != v2_uuid
    end

    test "raises when neither enum nor value level namespace is set" do
      # FileNamespaceId has file-level namespace but no enum-level namespace
      # File-level is not yet supported, so this should raise
      assert_raise ArgumentError, ~r/No namespace found/, fn ->
        UuidTemplate.extract_options(FileNamespaceId.IdentityVersion, :IDENTITY_VERSION_V1)
      end
    end
  end

  describe "compile-time validation errors" do
    # These test error messages raised during macro expansion.
    # We call the internal extract_options/2 directly since it's the same
    # code path that __using__ executes at compile time.

    test "raises for unknown version with available versions listed" do
      error =
        assert_raise ArgumentError, fn ->
          UuidTemplate.extract_options(OrderId.IdentityVersion, :IDENTITY_VERSION_V99)
        end

      assert error.message =~ "Identity version :IDENTITY_VERSION_V99 not found"
      assert error.message =~ "Available versions:"
      assert error.message =~ ":IDENTITY_VERSION_V1"
    end

    test "raises when version has no format option" do
      # When the proto value has no extensions at all, options is nil
      assert_raise ArgumentError, ~r/No options found for/, fn ->
        UuidTemplate.extract_options(NoFormatId.IdentityVersion, :IDENTITY_VERSION_V1)
      end
    end
  end

  describe "determinism" do
    test "same inputs always produce same UUID across multiple calls" do
      values = %{customer_id: "deterministic-test", order_number: "12345"}

      uuids = for _ <- 1..10, do: AcmeOrderId.uuid5(values)

      assert Enum.uniq(uuids) |> length() == 1
    end
  end
end
