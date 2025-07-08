defmodule Trogon.TypeProviderTest do
  use ExUnit.Case
  alias Trogon.TypeProvider.UnregisteredMappingError

  alias Trogon.TypeProvider.TestSupport.{
    SomethingWithEnforceKeysHappened,
    AccountCreated,
    AccountLocked,
    LedgerClosed,
    AccountTypeProvider,
    AccountWithPrefixTypeProvider,
    LedgerTypeProvider,
    MyAppTypeProvider,
    IAMTypeProvider
  }

  test "given a type provider when registering a mapping that already exists then raises an error" do
    expected_message = """
    Duplicate type registration for "ledger_halted"

    Already registered: LedgerHalted in InvalidTypeProvider
    Attempted to register: LedgerHalted in InvalidTypeProvider

    Each type must be unique within a TypeProvider.
    Consider using different types or check for duplicate registrations.
    """

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule LedgerHalted do
            defstruct [:id]
          end

          defmodule InvalidTypeProvider do
            use Trogon.TypeProvider
            register_type "ledger_halted", LedgerHalted
            register_type "ledger_halted", LedgerHalted
          end
        end
      )
    end)
  end

  test "given a type provider when registering a module that does not implement a struct then raises an error" do
    expected_message = """
    Invalid struct registration for type "email_sent"

    Expected: EmailSent to implement a struct
    Problem: Module does not define a struct

    To fix this, ensure your module defines a struct:

        defmodule EmailSent do
          defstruct [:field1, :field2]
        end
    """

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule EmailSent do
          end

          defmodule AnotherInvalidTypeProvider do
            use Trogon.TypeProvider
            register_type "email_sent", EmailSent
          end
        end
      )
    end)
  end

  test "given a type provider when calling to_type with a registered mapping then returns the mapped string" do
    assert {:ok, "account_created"} = AccountTypeProvider.to_type(%AccountCreated{})
  end

  test "given a type provider with prefix when calling to_type with a registered mapping then returns the mapped string" do
    assert {:ok, "accounts.account_created"} = AccountWithPrefixTypeProvider.to_type(%AccountCreated{})
    assert {:ok, "accounts.account_locked"} = AccountWithPrefixTypeProvider.to_type(%AccountLocked{})
  end

  test "given a type provider when calling to_type without a registered mapping then returns an error" do
    assert {:error, %UnregisteredMappingError{}} = LedgerTypeProvider.to_type(%LedgerClosed{})
  end

  test "given a type provider name when calling to_module with a registered mapping then returns the mapped module" do
    assert {:ok, AccountCreated} = AccountTypeProvider.to_module("account_created")
  end

  test "given a type provider composed by other type providers when calling to_type with a registered mapping then returns the mapped string" do
    assert {:ok, "account_created"} = MyAppTypeProvider.to_type(%AccountCreated{})
  end

  test "given a type provider when importing a broken type provider then raises an error" do
    expected_message = """
    Invalid TypeProvider import in InvalidTypeProvider

    Expected: BrokenTypeProvider to be a valid TypeProvider
    Problem: Module does not use Trogon.TypeProvider

    To fix this, ensure the module you're importing uses TypeProvider:

        defmodule BrokenTypeProvider do
          use Trogon.TypeProvider
          register_type "example", ExampleStruct
        end
    """

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule BrokenTypeProvider do
          end

          defmodule InvalidTypeProvider do
            use Trogon.TypeProvider
            import_type_provider BrokenTypeProvider
          end
        end
      )
    end)
  end

  test "given a type provider when importing two type providers that have conflicted mapping then raises an error" do
    expected_message = """
    Cannot import type "account_created" - already exists

    Trying to import from: Trogon.TypeProvider.TestSupport.IAMTypeProvider
    Into TypeProvider: ConflictedTypeProvider

    CONFLICT:
    • Type "account_created" is already registered as Trogon.TypeProvider.TestSupport.AccountCreated
    • Cannot import Trogon.TypeProvider.TestSupport.IAMAccountCreated because the type is taken

    SOLUTIONS:
    • Use different types in Trogon.TypeProvider.TestSupport.IAMTypeProvider
    • Add a prefix to avoid conflicts:
        use Trogon.TypeProvider, prefix: "iam."
    • Import types selectively instead of all at once
    """

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule ConflictedTypeProvider do
            use Trogon.TypeProvider
            import_type_provider AccountTypeProvider
            import_type_provider IAMTypeProvider
          end
        end
      )
    end)
  end

  test "given a type provider with a struct that has enforce_keys a when calling to_type then it returns the mapped string" do
    assert {:ok, "something_with_enforce_keys_happened"} =
             AccountTypeProvider.to_type(%SomethingWithEnforceKeysHappened{aggregate_id: nil})
  end
end
