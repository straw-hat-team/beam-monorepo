defmodule TestSupport.CommandRouterExample.CommandRouter do
  @moduledoc false
  use Trogon.Commanded.CommandRouter

  identify_aggregate(TestSupport.CommandRouterExample.BankAccount)

  dispatch(TestSupport.CommandRouterExample.CloseBankAccount,
    to: TestSupport.CommandRouterExample.CloseBankAccount,
    aggregate: TestSupport.CommandRouterExample.BankAccount
  )

  register_transaction_script(TestSupport.CommandRouterExample.OpenBankAccount)
end
