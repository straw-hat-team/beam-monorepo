defmodule TestSupport.CommandRouterExample.CloseBankAccount do
  @moduledoc false
  use OnePiece.Commanded.CommandHandler

  use OnePiece.Commanded.Command,
    aggregate_identifier: :uuid

  alias TestSupport.CommandRouterExample.{
    BankAccountClosed,
    CloseBankAccount,
    BankAccount
  }

  embedded_schema do
  end

  def handle(%BankAccount{} = _aggregate, %CloseBankAccount{} = command) do
    %BankAccountClosed{uuid: command.uuid}
  end
end
