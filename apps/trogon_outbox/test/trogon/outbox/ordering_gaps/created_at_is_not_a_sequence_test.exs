defmodule Trogon.Outbox.OrderingGaps.CreatedAtIsNotASequenceTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.Jobs
  alias Trogon.Outbox.TestSupport.SequenceGapDetector

  setup do
    Jobs.truncate!()
    :ok
  end

  test "two inserts in the same transaction share an identical created_at" do
    {:ok, {id1, id2}} =
      TestRepo.transaction(fn ->
        id1 = Jobs.insert!("a", "pending")
        id2 = Jobs.insert!("a", "pending")
        {id1, id2}
      end)

    assert Jobs.created_at!(id1) == Jobs.created_at!(id2)
  end

  test "a transaction that starts first but commits last gets an earlier created_at than a row already delivered" do
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          id = Jobs.insert!("a", "pending")
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

    id_b = Jobs.insert!("a", "pending")
    created_at_b = Jobs.created_at!(id_b)

    send(held_transaction.pid, :release)
    {:ok, ^id_a} = Task.await(held_transaction, 5_000)

    created_at_a = Jobs.created_at!(id_a)

    assert id_a < id_b
    assert NaiveDateTime.compare(created_at_a, created_at_b) == :lt

    # A consumer that already advanced its cursor to created_at_b, because b was
    # delivered first, will never see a under a `created_at > cursor` filter.
    assert Jobs.rows_with_created_at_after(created_at_b) == []
  end

  test "a per-source sequence number lets a consumer detect a missing event that created_at cannot" do
    assert SequenceGapDetector.missing([1, 3]) == [2]
  end
end
