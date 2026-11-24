defmodule Acme.Billing do
  @moduledoc false

  alias Acme.Billing.ChargeCard

  @router Trogon.Commanded.TestSupport.MockCommandedApplication

  def charge(card_id, cents, opts \\ []) do
    @router.dispatch(%ChargeCard{card_id: card_id, cents: cents}, opts)
  end
end
