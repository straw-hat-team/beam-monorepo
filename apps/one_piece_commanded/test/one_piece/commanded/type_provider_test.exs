defmodule OnePiece.Commanded.TypeProviderTest do
  use ExUnit.Case
  alias OnePiece.Commanded.TypeProvider

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
  end

  defmodule AccountWithPrefixTypeProvider do
    use TypeProvider, prefix: "accounts."
    register_type "account_created", AccountCreated
    register_type "account_locked", AccountLocked
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
            use OnePiece.Commanded.TypeProvider
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
            use OnePiece.Commanded.TypeProvider
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
    message =
      "%OnePiece.Commanded.TypeProviderTest.LedgerClosed{id: nil} is not registered in the OnePiece.Commanded.TypeProviderTest.LedgerTypeProvider type provider"

    assert_raise(ArgumentError, message, fn ->
      LedgerTypeProvider.to_string(%LedgerClosed{})
    end)
  end

  test "given a type provider name when calling to_struct with a registered mapping then returns the mapped struct" do
    assert %AccountCreated{} = AccountTypeProvider.to_struct("account_created")
  end

  test "given a type provider when calling to_struct without a registered mapping then raises an error" do
    message =
      ~s("ledger_closed" is not registered in the OnePiece.Commanded.TypeProviderTest.LedgerTypeProvider type provider)

    assert_raise(ArgumentError, message, fn ->
      LedgerTypeProvider.to_struct("ledger_closed")
    end)
  end

  test "given a type provider composed by other type providers when calling to_struct with a registered mapping then returns the mapped struct" do
    assert %AccountCreated{} = MyAppTypeProvider.to_struct("account_created")
  end

  test "given a type provider composed by other type providers when calling to_string with a registered mapping then returns the mapped string" do
    assert "account_created" == MyAppTypeProvider.to_string(%AccountCreated{})
  end

  test "given a type provider when importing a broken type provider then raises an error" do
    message = "InvalidTypeProvider import expected BrokenTypeProvider module to be a OnePiece.Commanded.TypeProvider"

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule BrokenTypeProvider do
          end

          defmodule InvalidTypeProvider do
            use OnePiece.Commanded.TypeProvider
            import_type_provider BrokenTypeProvider
          end
        end
      )
    end)
  end

  test "given a type provider when importing two type providers that have conflicted mapping then raises an error" do
    message =
      ~s(failed to import types from OnePiece.Commanded.TypeProviderTest.IAMTypeProvider into ConflictedTypeProvider because "account_created" already registered for OnePiece.Commanded.TypeProviderTest.AccountCreated registered in ConflictedTypeProvider)

    assert_raise(ArgumentError, message, fn ->
      Code.compile_quoted(
        quote do
          defmodule ConflictedTypeProvider do
            use OnePiece.Commanded.TypeProvider
            import_type_provider AccountTypeProvider
            import_type_provider IAMTypeProvider
          end
        end
      )
    end)
  end
end
