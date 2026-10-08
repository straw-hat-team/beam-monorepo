defmodule Trogon.Outbox.OrderingGaps.IdOrderVsCommitOrderTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ChainGate
  alias Trogon.Outbox.TestSupport.Jobs

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a transaction that commits later can still be decided first, publishing out of id order" do
    source = "concurrent-1"
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          id = Jobs.insert!(source, "pending")
          send(test_pid, {:inserted, id})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the held transaction did not receive the release signal")
          end

          id
        end)
      end)

    id_a =
      receive do
        {:inserted, id} -> id
      after
        5_000 -> flunk("the held transaction did not insert in time")
      end

    id_b = Jobs.insert!(source, "pending")
    decision_b = ChainGate.decide(TestRepo, source, id_b, :ignore)
    published = if decision_b == :publish, do: [id_b], else: []

    send(held_transaction.pid, :release)
    {:ok, ^id_a} = Task.await(held_transaction, 5_000)

    decision_a = ChainGate.decide(TestRepo, source, id_a, :ignore)
    published = if decision_a == :publish, do: published ++ [id_a], else: published

    assert id_a < id_b
    assert published == [id_b, id_a]
  end

  test "an advisory lock taken before insert serializes commits so id order matches commit order" do
    source = "concurrent-2"
    test_pid = self()

    first =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          Jobs.lock_source!(source)
          id = Jobs.insert!(source, "pending")
          send(test_pid, :locked)

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the lock holder did not receive the release signal")
          end

          id
        end)
      end)

    receive do
      :locked -> :ok
    after
      5_000 -> flunk("the lock holder did not acquire the lock in time")
    end

    second =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          Jobs.lock_source!(source)
          Jobs.insert!(source, "pending")
        end)
      end)

    assert Task.yield(second, 300) == nil

    send(first.pid, :release)

    {:ok, id_a} = Task.await(first, 5_000)
    {:ok, id_b} = Task.await(second, 5_000)

    assert id_a < id_b

    decision_a = ChainGate.decide(TestRepo, source, id_a, :ignore)
    published = if decision_a == :publish, do: [id_a], else: []
    if decision_a == :publish, do: Jobs.mark_completed!(id_a)

    decision_b = ChainGate.decide(TestRepo, source, id_b, :ignore)
    published = if decision_b == :publish, do: published ++ [id_b], else: published

    assert published == [id_a, id_b]
  end
end
