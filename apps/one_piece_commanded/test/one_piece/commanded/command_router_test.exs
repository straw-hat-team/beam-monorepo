defmodule OnePiece.Commanded.CommandRouterTest do
  use ExUnit.Case, async: true

  alias TestSupport.CommandRouterExample.{
    CommandRouter,
    OpenBankAccount,
    CloseBankAccount,
    BankAccount
  }

  @dispatch_opts [
    application: TestSupport.DefaultApp,
    returning: :execution_result
  ]

  setup do
    start_supervised!(TestSupport.DefaultApp)
    :ok
  end

  describe "identify_aggregate/1" do
    test "identifies an aggregate" do
      {:ok, result} =
        %{uuid: "uuid-1"}
        |> CloseBankAccount.new!()
        |> CommandRouter.dispatch(@dispatch_opts)

      assert result.aggregate_uuid == "bank-account2-uuid-1"
      assert result.aggregate_state == %BankAccount{closed?: true, uuid: "uuid-1"}
    end
  end

  describe "dispatch_transaction/2" do
    test "dispatches a transaction" do
      {:ok, result} =
        %{uuid: "uuid-1"}
        |> OpenBankAccount.new!()
        |> CommandRouter.dispatch(@dispatch_opts)

      assert result.aggregate_uuid == "bank-account-uuid-1"
      assert result.aggregate_state == %OpenBankAccount.Aggregate{uuid: "uuid-1"}
    end
  end
end
