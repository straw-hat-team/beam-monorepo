defmodule Trogon.TypeProvider.TestSupport do
  defmodule TestEvent do
    defstruct [:id, :data]
  end

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

  defmodule IAMAccountCreated do
    defstruct [:id]
  end

  # Test TypeProviders
  defmodule TestTypeProvider do
    use Trogon.TypeProvider

    register_type "test_event", TestEvent
    register_type "another_event", TestEvent
    register_type "user_created", TestEvent
  end

  defmodule AccountTypeProvider do
    use Trogon.TypeProvider

    register_type "account_created", AccountCreated
    register_type "something_with_enforce_keys_happened", SomethingWithEnforceKeysHappened
  end

  defmodule AccountWithPrefixTypeProvider do
    use Trogon.TypeProvider, prefix: "accounts."

    register_type "account_created", AccountCreated
    register_type "account_locked", AccountLocked
  end

  defmodule IAMTypeProvider do
    use Trogon.TypeProvider

    register_type "account_created", IAMAccountCreated
  end

  defmodule LedgerTypeProvider do
    use Trogon.TypeProvider

    register_type "ledger_initialized", LedgerInitialized
  end

  defmodule MyAppTypeProvider do
    use Trogon.TypeProvider

    import_type_provider AccountTypeProvider
    import_type_provider LedgerTypeProvider
  end

  defmodule EmptyTypeProvider do
    use Trogon.TypeProvider
  end

  defmodule SingleMappingTypeProvider do
    use Trogon.TypeProvider

    register_type "test_event", TestEvent
  end
end
