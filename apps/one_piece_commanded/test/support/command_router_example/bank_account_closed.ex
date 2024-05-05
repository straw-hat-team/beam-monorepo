defmodule TestSupport.CommandRouterExample.BankAccountClosed do
  @moduledoc false
  use OnePiece.Commanded.Event, aggregate_identifier: :uuid

  embedded_schema do
  end
end
