defmodule TestSupport.CommandRouterExample.BankAccountOpened.BankAccountType do
  @moduledoc false

  use OnePiece.Commanded.Enum,
    values: [:business, :personal]
end

defmodule TestSupport.CommandRouterExample.BankAccountOpened do
  @moduledoc false
  use OnePiece.Commanded.Event, aggregate_identifier: :uuid

  embedded_schema do
    field :type, TestSupport.CommandRouterExample.BankAccountOpened.BankAccountType
  end
end
