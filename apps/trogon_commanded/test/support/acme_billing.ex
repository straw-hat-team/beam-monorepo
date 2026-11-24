defmodule Acme.Billing do
  @moduledoc false

  defmodule ChargeCard do
    @moduledoc false
    defstruct [:card_id, :cents]
  end

  @router Trogon.Commanded.TestSupport.MockCommandRouter

  def charge(card_id, cents, opts \\ []) do
    @router.dispatch(%ChargeCard{card_id: card_id, cents: cents}, opts)
  end
end
