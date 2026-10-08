defmodule Trogon.Outbox.OrderingGaps.PerSourceOrderingTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ChainGate
  alias Trogon.Outbox.TestSupport.Jobs

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a stuck head on one source does not block delivery on another source" do
    _stuck_head = Jobs.insert!("a", "executing")
    b1 = Jobs.insert!("b", "pending")
    a_next = Jobs.insert!("a", "pending")
    b2 = Jobs.insert!("b", "pending")
    b3 = Jobs.insert!("b", "pending")

    assert ChainGate.decide(TestRepo, "a", a_next, :ignore) == :wait

    published =
      Enum.reduce([b1, b2, b3], [], fn id, acc ->
        case ChainGate.decide(TestRepo, "b", id, :ignore) do
          :publish ->
            Jobs.mark_completed!(id)
            acc ++ [id]

          _ ->
            acc
        end
      end)

    assert published == [b1, b2, b3]
    assert ChainGate.decide(TestRepo, "a", a_next, :ignore) == :wait
  end
end
