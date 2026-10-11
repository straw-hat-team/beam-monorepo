defmodule Trogon.Commanded.TestSupport.CommandRouterExample.CloseBankAccount do
  @moduledoc false
  use Trogon.Commanded.CommandHandler

  use Trogon.Commanded.Command,
    aggregate_identifier: :uuid

  alias Trogon.Commanded.TestSupport.CommandRouterExample.{
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
