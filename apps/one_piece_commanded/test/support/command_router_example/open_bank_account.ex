defmodule TestSupport.CommandRouterExample.OpenBankAccount.Aggregate do
  @moduledoc false
  use OnePiece.Commanded.Aggregate, identifier: :uuid
  alias TestSupport.CommandRouterExample.BankAccountOpened

  embedded_schema do
  end

  @impl OnePiece.Commanded.Aggregate
  def apply(aggregate, %BankAccountOpened{} = event) do
    aggregate
    |> Map.put(:uuid, event.uuid)
  end
end

defmodule TestSupport.CommandRouterExample.OpenBankAccount do
  @moduledoc false
  use OnePiece.Commanded.CommandHandler

  use OnePiece.Commanded.Command,
    aggregate_identifier: :uuid,
    stream_prefix: "bank-account-"

  alias TestSupport.CommandRouterExample.{
    BankAccountOpened,
    OpenBankAccount
  }

  embedded_schema do
  end

  def handle(%OpenBankAccount.Aggregate{} = _aggregate, %OpenBankAccount{} = command) do
    %BankAccountOpened{uuid: command.uuid}
  end
end
