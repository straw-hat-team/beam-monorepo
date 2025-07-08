defmodule Trogon.TypeProvider.UnregisteredMappingErrorTest do
  use ExUnit.Case
  alias Trogon.TypeProvider.UnregisteredMappingError
  alias Trogon.TypeProvider.TestSupport.TestTypeProvider

  describe "exception/1" do
    test "creates exception with proper fields" do
      error =
        UnregisteredMappingError.exception(
          mapping: "unknown_type",
          type_provider: TestTypeProvider
        )

      assert error.mapping == "unknown_type"
      assert error.type_provider == TestTypeProvider
    end

    test "handles missing fields gracefully" do
      error = UnregisteredMappingError.exception([])

      assert error.mapping == nil
      assert error.type_provider == nil
    end
  end

  describe "message/1" do
    test "basic error message for unknown type" do
      error = %UnregisteredMappingError{
        mapping: "unknown_type",
        type_provider: TestTypeProvider
      }

      message = UnregisteredMappingError.message(error)

      assert String.contains?(message, "Unregistered mapping for \"unknown_type\"")
      assert String.contains?(message, "TestTypeProvider")
    end

    test "handles different type provider modules" do
      error = %UnregisteredMappingError{
        mapping: "unknown_type",
        type_provider: String
      }

      message = UnregisteredMappingError.message(error)

      assert String.contains?(message, "Unregistered mapping for \"unknown_type\"")
      assert String.contains?(message, "String")
    end

    test "handles non-string mappings" do
      error = %UnregisteredMappingError{
        mapping: %{some: "struct"},
        type_provider: TestTypeProvider
      }

      message = UnregisteredMappingError.message(error)

      assert String.contains?(message, "Unregistered mapping for %{some: \"struct\"}")
      assert String.contains?(message, "TestTypeProvider")
    end
  end

  describe "integration with actual TypeProvider" do
    test "tuple error is returned with proper message when accessing unknown type" do
      assert {:error, %UnregisteredMappingError{}} = TestTypeProvider.to_module("nonexistent_type")
    end

    test "error includes proper error information when returned" do
      case TestTypeProvider.to_module("nonexistent_type") do
        {:error, e} ->
          message = Exception.message(e)
          assert String.contains?(message, "Unregistered mapping for \"nonexistent_type\"")
          assert String.contains?(message, "TestTypeProvider")
      end
    end
  end
end
