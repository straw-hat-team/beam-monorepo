defmodule Trogon.Outbox.OrderingGaps.SkipPolicyTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ChainGate
  alias Trogon.Outbox.TestSupport.Jobs

  setup do
    Jobs.truncate!()
    :ok
  end

  test "an ignore policy publishes the next event even though its predecessor was discarded" do
    source = "order-1"
    discarded_id = Jobs.insert!(source, "discarded")
    next_id = Jobs.insert!(source, "pending")

    decision = ChainGate.decide(TestRepo, source, next_id, :ignore)
    published = if decision == :publish, do: [next_id], else: []

    assert decision == :publish
    assert published == [next_id]
    refute discarded_id in published
  end

  test "a hold policy blocks the next event instead of letting it skip past the gap" do
    source = "order-2"
    _discarded_id = Jobs.insert!(source, "discarded")
    next_id = Jobs.insert!(source, "pending")

    decision = ChainGate.decide(TestRepo, source, next_id, :hold)

    assert decision == :hold
  end
end
