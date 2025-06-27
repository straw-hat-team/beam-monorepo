defmodule TestSupport.CommandRouterExample.BankAccountClosed do
  @moduledoc false
  use Trogon.Commanded.Event, aggregate_identifier: :uuid

  embedded_schema do
  end
end
