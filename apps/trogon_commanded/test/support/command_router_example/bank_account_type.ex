defmodule TestSupport.CommandRouterExample.BankAccountType do
  @moduledoc false

  use Trogon.Commanded.Enum,
    values: [:business, :personal]
end
