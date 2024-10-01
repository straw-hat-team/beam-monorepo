defmodule TestSupport.CommandRouterExample.BankAccountType do
  @moduledoc false

  use OnePiece.Commanded.Enum,
    values: [:business, :personal]
end
