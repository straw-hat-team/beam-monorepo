defmodule Trogon.Outbox.PostgresOutbox.SavepointTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  # Ecto's own nested `Repo.transaction/2` has no savepoint isolation: rolling back the inner
  # call aborts the whole outer transaction (see the Ecto.Repo moduledoc's "nested transactions"
  # section). A caller that wants to undo part of a business transaction without losing the rest
  # issues `SAVEPOINT` directly, so that is what these tests drive `append/4` through.

  test "an append inside a rolled-back savepoint leaves no seq gap, no counter advance, and the relay never sees it",
       %{prefix: prefix} do
    start_relay!(prefix)
    open = open_transaction()

    [first] =
      run_in(open, fn ->
        {:ok, events} = Trogon.Outbox.append(TestRepo, "source-a", "before-savepoint", prefix: prefix)
        events
      end)

    assert first.position.seq.value == 1

    rolled_back =
      run_in(open, fn ->
        SQL.query!(TestRepo, "SAVEPOINT sp1")
        {:ok, [event]} = Trogon.Outbox.append(TestRepo, "source-a", "inside-savepoint", prefix: prefix)
        SQL.query!(TestRepo, "ROLLBACK TO SAVEPOINT sp1")
        SQL.query!(TestRepo, "RELEASE SAVEPOINT sp1")
        event
      end)

    counter_seq_after_rollback =
      run_in(open, fn ->
        %Postgrex.Result{rows: [[seq]]} =
          SQL.query!(TestRepo, ~s(SELECT seq FROM "#{prefix}".outbox_sources WHERE source = $1), ["source-a"])

        seq
      end)

    assert counter_seq_after_rollback == 1

    [second] =
      run_in(open, fn ->
        {:ok, events} = Trogon.Outbox.append(TestRepo, "source-a", "after-savepoint", prefix: prefix)
        events
      end)

    finish(open)

    assert second.position.seq.value == 2
    assert rolled_back.payload == "inside-savepoint"
    assert [%{payload: "before-savepoint"}, %{payload: "after-savepoint"}] = collect_events(2)
  end

  test "an append inside a released savepoint publishes with the next seq like any other append",
       %{prefix: prefix} do
    start_relay!(prefix)

    {:ok, [outer, inner]} =
      TestRepo.transaction(fn ->
        {:ok, [outer_event]} = Trogon.Outbox.append(TestRepo, "source-a", "outer", prefix: prefix)

        SQL.query!(TestRepo, "SAVEPOINT sp1")
        {:ok, [inner_event]} = Trogon.Outbox.append(TestRepo, "source-a", "inner-savepoint", prefix: prefix)
        SQL.query!(TestRepo, "RELEASE SAVEPOINT sp1")

        [outer_event, inner_event]
      end)

    assert outer.position.seq.value == 1
    assert inner.position.seq.value == 2
    assert [%{payload: "outer"}, %{payload: "inner-savepoint"}] = collect_events(2)
  end
end
