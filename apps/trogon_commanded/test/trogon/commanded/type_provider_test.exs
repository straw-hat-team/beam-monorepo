defmodule Trogon.Commanded.TypeProviderTest do
  use ExUnit.Case
  alias Trogon.Commanded.TypeProvider
  alias Trogon.Commanded.TypeProvider.UnregisteredMappingError

  alias Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountOpened, as: ProtoAccountOpened
  alias Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountClosed, as: ProtoAccountClosed
  alias Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.TransferInitiated, as: ProtoTransferInitiated

  defmodule SomethingWithEnforceKeysHappened do
    @enforce_keys [:aggregate_id]
    defstruct [:aggregate_id, :foo, :bar]
  end

  defmodule AccountCreated do
    defstruct [:id]
  end

  defmodule AccountClosed do
    defstruct [:id]
  end

  defmodule AccountLocked do
    defstruct [:id]
  end

  defmodule LedgerClosed do
    defstruct [:id]
  end

  defmodule LedgerInitialized do
    defstruct [:id]
  end

  defmodule AccountTypeProvider do
    use TypeProvider
    register_type "account_created", AccountCreated
    register_type "something_with_enforce_keys_happened", SomethingWithEnforceKeysHappened
  end

  defmodule AccountWithPrefixTypeProvider do
    use TypeProvider, prefix: "accounts."
    register_type "account_created", AccountCreated
    register_type "account_locked", AccountLocked
  end

  defmodule ProtobufTypeProvider do
    use TypeProvider
    register_protobuf_message ProtoAccountOpened
    register_protobuf_message ProtoAccountClosed
  end

  defmodule ProtobufWithPrefixTypeProvider do
    use TypeProvider, prefix: "events."
    register_protobuf_message ProtoTransferInitiated
  end

  defmodule MixedTypeProvider do
    use TypeProvider
    register_type "account_created", AccountCreated
    register_protobuf_message ProtoAccountOpened
  end

  defmodule IAMAccountCreated do
    defstruct [:id]
  end

  defmodule IAMTypeProvider do
    use TypeProvider
    register_type "account_created", IAMAccountCreated
  end

  defmodule LedgerTypeProvider do
    use TypeProvider
    register_type "ledger_initialized", LedgerInitialized
  end

  defmodule MyAppTypeProvider do
    use TypeProvider
    import_type_provider AccountTypeProvider
    import_type_provider LedgerTypeProvider
  end

  test "given a type provider when registering a mapping that already exists then raises an error" do
    message = ~s("ledger_halted" already registered with LedgerHalted in InvalidTypeProvider)

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule LedgerHalted do
            defstruct [:id]
          end

          defmodule InvalidTypeProvider do
            use Trogon.Commanded.TypeProvider
            register_type "ledger_halted", LedgerHalted
            register_type "ledger_halted", LedgerHalted
          end
        end
      )
    end)
  end

  test "given a type provider when registering a module that does not implements a struct then raises an error" do
    message = ~s("email_sent" registration expected EmailSent to be a module that implements a struct)

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule EmailSent do
          end

          defmodule AnotherInvalidTypeProvider do
            use Trogon.Commanded.TypeProvider
            register_type "email_sent", EmailSent
          end
        end
      )
    end)
  end

  test "given a type provider when calling to_string with a registered mapping then returns the mapped string" do
    assert "account_created" == AccountTypeProvider.to_string(%AccountCreated{})
  end

  test "given a type provider with prefix when calling to_string with a registered mapping then returns the mapped string" do
    assert "accounts.account_created" == AccountWithPrefixTypeProvider.to_string(%AccountCreated{})
    assert "accounts.account_locked" == AccountWithPrefixTypeProvider.to_string(%AccountLocked{})
  end

  test "given a type provider when calling to_string without a registered mapping then raises an error" do
    assert_raise(UnregisteredMappingError, fn ->
      LedgerTypeProvider.to_string(%LedgerClosed{})
    end)
  end

  test "given a type provider name when calling to_struct with a registered mapping then returns the mapped struct" do
    assert %AccountCreated{} = AccountTypeProvider.to_struct("account_created")
  end

  test "given a type provider when calling to_struct without a registered mapping then raises an error" do
    assert_raise(UnregisteredMappingError, fn ->
      LedgerTypeProvider.to_struct("ledger_closed")
    end)
  end

  test "given a type provider when calling fetch_struct_module with a registered mapping then returns the mapped struct" do
    assert {:ok, AccountCreated} = AccountTypeProvider.fetch_struct_module("account_created")
  end

  test "given a type provider when calling fetch_struct_module without a registered mapping then raises an error" do
    assert {:error, %UnregisteredMappingError{}} =
             AccountTypeProvider.fetch_struct_module("ledger_closed")
  end

  test "given a type provider composed by other type providers when calling to_struct with a registered mapping then returns the mapped struct" do
    assert %AccountCreated{} = MyAppTypeProvider.to_struct("account_created")
  end

  test "given a type provider composed by other type providers when calling to_string with a registered mapping then returns the mapped string" do
    assert "account_created" == MyAppTypeProvider.to_string(%AccountCreated{})
  end

  test "given a type provider when importing a broken type provider then raises an error" do
    message = "InvalidTypeProvider import expected BrokenTypeProvider module to be a Trogon.Commanded.TypeProvider"

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule BrokenTypeProvider do
          end

          defmodule InvalidTypeProvider do
            use Trogon.Commanded.TypeProvider
            import_type_provider BrokenTypeProvider
          end
        end
      )
    end)
  end

  test "given a type provider when importing two type providers that have conflicted mapping then raises an error" do
    message =
      ~s(failed to import types from Trogon.Commanded.TypeProviderTest.IAMTypeProvider into ConflictedTypeProvider because "account_created" already registered for Trogon.Commanded.TypeProviderTest.AccountCreated registered in ConflictedTypeProvider)

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule ConflictedTypeProvider do
            use Trogon.Commanded.TypeProvider
            import_type_provider AccountTypeProvider
            import_type_provider IAMTypeProvider
          end
        end
      )
    end)
  end

  test "given a type provider with a struct that has enforce_keys a when calling to_string then it returns the mapped string" do
    assert "something_with_enforce_keys_happened" ==
             AccountTypeProvider.to_string(%SomethingWithEnforceKeysHappened{aggregate_id: nil})
  end

  test "given a type provider with a struct that has enforce_keys a when calling to_struct then it returns the mapped struct" do
    assert struct(SomethingWithEnforceKeysHappened) ==
             AccountTypeProvider.to_struct("something_with_enforce_keys_happened")
  end

  test "given a type provider with protobuf message when calling to_string then returns the full_name" do
    assert "trogon.commanded.demo.AccountOpened" ==
             ProtobufTypeProvider.to_string(%ProtoAccountOpened{})
  end

  test "given a type provider with protobuf message when calling to_struct then returns the struct" do
    assert %ProtoAccountOpened{} = ProtobufTypeProvider.to_struct("trogon.commanded.demo.AccountOpened")
  end

  test "given a type provider with prefix and protobuf message when calling to_string then returns prefixed full_name" do
    assert "events.trogon.commanded.demo.TransferInitiated" ==
             ProtobufWithPrefixTypeProvider.to_string(%ProtoTransferInitiated{})
  end

  test "given a type provider with prefix and protobuf message when calling to_struct then returns the struct" do
    assert %ProtoTransferInitiated{} =
             ProtobufWithPrefixTypeProvider.to_struct("events.trogon.commanded.demo.TransferInitiated")
  end

  test "given a type provider with mixed registrations when calling to_string then works for both" do
    assert "account_created" == MixedTypeProvider.to_string(%AccountCreated{})
    assert "trogon.commanded.demo.AccountOpened" == MixedTypeProvider.to_string(%ProtoAccountOpened{})
  end

  test "given a type provider when registering a module without full_name/0 then raises an error" do
    expected_message =
      "InvalidProtobufTypeProvider registration expected NotAProtobuf to be a Protobuf message with full_name/0"

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule NotAProtobuf do
            defstruct [:id]
          end

          defmodule InvalidProtobufTypeProvider do
            use Trogon.Commanded.TypeProvider
            register_protobuf_message NotAProtobuf
          end
        end
      )
    end)
  end

  test "given a type provider when registering duplicate protobuf messages then raises an error" do
    expected_message =
      ~s("trogon.commanded.demo.AccountOpened" already registered with Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountOpened in DuplicateProtobufTypeProvider)

    assert_raise(ArgumentError, expected_message, fn ->
      Code.compile_quoted(
        quote do
          defmodule DuplicateProtobufTypeProvider do
            use Trogon.Commanded.TypeProvider

            register_protobuf_message Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountOpened
            register_protobuf_message Trogon.Commanded.TestSupport.Trogon.Commanded.Demo.AccountOpened
          end
        end
      )
    end)
  end
end
