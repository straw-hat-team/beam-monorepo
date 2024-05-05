defmodule TestSupport.CommandRouterExample.BankAccount do
  @moduledoc false
  use OnePiece.Commanded.Aggregate,
    identifier: :uuid,
    stream_prefix: "bank-account2-"

  alias TestSupport.CommandRouterExample.{BankAccountOpened, BankAccountClosed}

  embedded_schema do
    field :closed?, :boolean, default: false
  end

  @impl OnePiece.Commanded.Aggregate
  def apply(aggregate, %BankAccountOpened{} = event) do
    aggregate
    |> Map.put(:uuid, event.uuid)
  end

  @impl OnePiece.Commanded.Aggregate
  def apply(aggregate, %BankAccountClosed{} = event) do
    aggregate
    |> Map.put(:uuid, event.uuid)
    |> Map.put(:closed?, true)
  end
end
