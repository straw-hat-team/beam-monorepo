defmodule TestSupport.CommandRouterExample.CommandRouter do
  @moduledoc false
  use OnePiece.Commanded.CommandRouter
  register_transaction_script(TestSupport.CommandRouterExample.OpenBankAccount)
end
