defmodule Trogon.Commanded.TestSupport.CommandRouterExample.CommandRouter do
  @moduledoc false
  use Trogon.Commanded.CommandRouter

  identify_aggregate(Trogon.Commanded.TestSupport.CommandRouterExample.BankAccount)

  dispatch(Trogon.Commanded.TestSupport.CommandRouterExample.CloseBankAccount,
    to: Trogon.Commanded.TestSupport.CommandRouterExample.CloseBankAccount,
    aggregate: Trogon.Commanded.TestSupport.CommandRouterExample.BankAccount
  )

  register_transaction_script(Trogon.Commanded.TestSupport.CommandRouterExample.OpenBankAccount)
end
