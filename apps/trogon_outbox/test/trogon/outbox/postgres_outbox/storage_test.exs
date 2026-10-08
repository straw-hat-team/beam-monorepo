defmodule Trogon.Outbox.PostgresOutbox.StorageTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Event, Partition, Postgres, Relay, Retention}

  setup do
    SQL.query!(TestRepo, "CREATE EXTENSION IF NOT EXISTS pgstattuple")
    :ok
  end

  test "appending and publishing leaves no dead tuples on the events table, only rolled-back appends do",
       %{prefix: prefix} do
    start_relay!(prefix, batch_size: 50)

    committed = Enum.flat_map(1..300, &append!(prefix, "source-#{rem(&1, 10)}", "event-#{&1}"))
    collect_events(length(committed))

    assert events_tuples(prefix) == %{live: 300, dead: 0}

    rolled_back =
      Enum.count(1..20, fn n ->
        {:error, :aborted} =
          TestRepo.transaction(fn ->
            Trogon.Outbox.append(TestRepo, "source-#{n}", "rolled-back", prefix: prefix)
            TestRepo.rollback(:aborted)
          end)
      end)

    %{live: live, dead: dead} = events_tuples(prefix)

    assert rolled_back == 20
    assert live == 300
    assert dead in 1..rolled_back
  end

  test "counter bumps are heap-only tuple updates when every update fits the fillfactor reserve",
       %{prefix: prefix} do
    assert_fillfactor(prefix, "outbox_sources", 70)
    assert_no_index_on(prefix, "outbox_sources", ["seq", "xid"])

    sources = Enum.map(1..4, &"source-#{&1}")
    Enum.each(sources, &append!(prefix, &1, "first"))

    updates = max_hot_updates(prefix, "outbox_sources")

    {:ok, {total, hot}} =
      TestRepo.transaction(fn ->
        for n <- 1..updates, do: append!(prefix, Enum.at(sources, rem(n, 4)), "event-#{n}")
        xact_tuple_stats(prefix, "outbox_sources")
      end)

    assert {total, hot} == {updates, updates}
  end

  test "cursor advances are heap-only tuple updates when every update fits the fillfactor reserve",
       %{prefix: prefix} do
    assert_fillfactor(prefix, "outbox_cursors", 50)
    assert_no_index_on(prefix, "outbox_cursors", ["xid", "id", "advanced_at"])

    append!(prefix, "source-a", "first")
    start_relay!(prefix, batch_size: 1)
    collect_events(1)

    before =
      wait_until(fn ->
        case table_stats(prefix, "outbox_cursors") do
          {1, 1} = stats -> stats
          _not_yet_advanced -> nil
        end
      end)

    updates = max_hot_updates(prefix, "outbox_cursors")

    appended = Enum.flat_map(1..updates, &append!(prefix, "source-a", "event-#{&1}"))
    collect_events(length(appended))

    {total, hot} = stats_delta_until(prefix, "outbox_cursors", before, updates)

    assert {total, hot} == {updates, updates}
  end

  test "appends to the day being dropped never stall, succeeding until the moment it is gone",
       %{prefix: prefix} do
    today = Date.utc_today()
    start_relay!(prefix)

    appended = Enum.flat_map(1..20, fn n -> append!(prefix, "source-#{rem(n, 5)}", "event-#{n}") end)
    collect_events(length(appended))

    {:ok, stop} = Agent.start_link(fn -> false end)

    # Proves a write succeeds while the day is still live, without relying on the concurrent writer
    # below ever getting scheduled before retention wins the race, which it sometimes does almost
    # immediately now that nothing holds it back artificially.
    assert attempt_write(prefix, 0) == :ok

    # Bounded, not an endless stream: an unbounded writer can keep outrunning the relay for as
    # long as the suite around it is busy, so no fixed wait_until timeout would ever be safe. A
    # fixed backlog gives the relay a fixed amount of catching up to do no matter how long the
    # detach race itself takes.
    writer =
      Task.async(fn ->
        1..300
        |> Stream.take_while(fn _ -> not Agent.get(stop, & &1) end)
        |> Enum.map(&attempt_write(prefix, &1))
      end)

    wait_until(
      fn ->
        {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
        today in result.dropped
      end,
      30_000
    )

    Agent.update(stop, fn _ -> true end)
    outcomes = Task.await(writer, 30_000)

    # A detach that finds a late write still attaches the day back instead of dropping it, so a
    # write can succeed again after an earlier one already saw :no_partition; that oscillation is
    # expected, not a stall. The writer can also legitimately make its very last attempt the moment
    # the day is dropped and still have it land, since `wait_until` only stops it afterward, so the
    # list itself does not have to end on :no_partition, or even contain an :ok at all if retention
    # won the race before the writer got scheduled. What must hold is that the day is gone for good
    # once the writer is confirmed stopped: a write attempted now, unambiguously after, fails.
    assert outcomes != []
    assert attempt_write(prefix, :after_stop) == :no_partition
  end

  test "relay batch reads never stall while an older day is dropped with DETACH PARTITION CONCURRENTLY",
       %{prefix: prefix} do
    old_day = Date.add(Date.utc_today(), -1)
    Retention.create_partitions(TestRepo, prefix: prefix, today: old_day, days_ahead: 0)

    append!(prefix, "source-a", "before-detach-waits")

    holder = open_transaction()
    run_in(holder, fn -> lock_partition!(prefix, old_day) end)

    drop =
      Task.async(fn ->
        Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(old_day, 1), lock_timeout: 10_000)
      end)

    start_relay!(prefix, batch_size: 10)

    assert [%{payload: "before-detach-waits"}] = collect_events(1)
    assert Task.yield(drop, 0) == nil, "DETACH should still be waiting on the lock held by the other transaction"
    wait_until(fn -> detaching?(prefix, old_day) end, 2_000)
    assert Task.yield(drop, 0) == nil, "DETACH should still be waiting on the lock held by the other transaction"

    finish(holder)

    assert {:ok, %{dropped: dropped}} = Task.await(drop, 10_000)
    assert old_day in dropped
  end

  test "retention drops a published day whole, leaves no dead tuples, and seq continues after it",
       %{prefix: prefix} do
    today = Date.utc_today()
    start_relay!(prefix)

    appended = Enum.flat_map(1..50, fn n -> append!(prefix, "source-#{rem(n, 5)}", "event-#{n}") end)
    collect_events(length(appended))

    wait_until(fn ->
      {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
      today in result.dropped
    end)

    assert today not in Retention.partitions(TestRepo, prefix: prefix)
    assert event_count(prefix) == 0
    assert Enum.all?(Retention.partitions(TestRepo, prefix: prefix), &(partition_tuples(prefix, &1).dead == 0))

    Retention.create_partitions(TestRepo, prefix: prefix, today: today, days_ahead: 0)
    [next] = append!(prefix, "source-0", "after-retention")

    assert next.position.seq.value == 11
    assert [%{payload: "after-retention"}] = collect_events(1)
  end

  test "retention keeps a day that still has unpublished events", %{prefix: prefix} do
    today = Date.utc_today()
    append!(prefix, "source-a", "unpublished")

    assert {:ok, %{dropped: dropped, kept: kept}} =
             Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))

    assert today not in dropped
    assert {today, :unpublished} in kept
    assert event_count(prefix) == 1
  end

  test "retention keeps a day while a transaction already writing to it is still open",
       %{prefix: prefix} do
    today = Date.utc_today()
    open = open_transaction()
    run_in(open, fn -> Trogon.Outbox.append(TestRepo, "source-a", "still-writing", prefix: prefix) end)

    assert {:ok, %{kept: kept}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert {today, :locked} in kept
    assert today in Retention.partitions(TestRepo, prefix: prefix)

    finish(open)
  end

  test "a detach that timed out mid-wait still lets the late event publish and the day drop afterward",
       %{prefix: prefix} do
    today = Date.utc_today()
    {:ok, _older_days} = Retention.drop_partitions(TestRepo, prefix: prefix, before: today)
    open = open_transaction()
    run_in(open, fn -> Trogon.Outbox.append(TestRepo, "source-a", "committed-after-timeout", prefix: prefix) end)

    assert {:ok, %{kept: kept}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert {today, :locked} in kept

    finish(open)

    assert {:ok, %{kept: kept}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert {today, :unpublished} in kept

    start_relay!(prefix)
    assert [%{payload: "committed-after-timeout"}] = collect_events(1)

    wait_until(fn ->
      {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
      today in result.dropped
    end)
  end

  test "retention does not wait on an open transaction that has not written to the day being dropped",
       %{prefix: prefix} do
    today = Date.utc_today()
    open = open_transaction()
    run_in(open, &current_xid!/0)

    assert {:ok, %{dropped: dropped}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert today in dropped
    assert today not in Retention.partitions(TestRepo, prefix: prefix)

    finish(open)
  end

  test "retention keeps a day until every relay with a cursor on it catches up, not only the first",
       %{prefix: prefix} do
    today = Date.utc_today()
    append!(prefix, "source-a", "event")

    start_relay!(prefix, relay: "relay-a")
    collect_events(1)

    count = Relay.Store.partition_count!(TestRepo, prefix)
    Relay.Store.load_cursors!(TestRepo, prefix, "relay-b", Partition.all(count))

    assert {:ok, %{kept: kept}} =
             Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))

    assert {today, :unpublished} in kept
    assert today in Retention.partitions(TestRepo, prefix: prefix)

    start_relay!(prefix, relay: "relay-b")
    collect_events(1)

    wait_until(fn ->
      {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
      today in result.dropped
    end)
  end

  test "retention keeps a day for an event a transaction committed late into it, until the relay reads it",
       %{prefix: prefix} do
    today = Date.utc_today()

    open = open_transaction()

    [late] =
      run_in(open, fn ->
        {:ok, events} = Trogon.Outbox.append(TestRepo, "late-source", "late-event", prefix: prefix)
        events
      end)

    assert {:ok, %{kept: kept}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert {today, :locked} in kept

    finish(open)

    assert {:ok, %{kept: kept}} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
    assert {today, :unpublished} in kept
    assert today in Retention.partitions(TestRepo, prefix: prefix)

    start_relay!(prefix)
    assert [%{payload: "late-event"}] = collect_events(1)
    assert late.payload == "late-event"

    wait_until(fn ->
      {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
      today in result.dropped
    end)
  end

  test "retention never drops an event appended between the unpublished check and the detach",
       %{prefix: prefix} do
    today = Date.utc_today()
    start_relay!(prefix, batch_size: 50)

    {:ok, stop} = Agent.start_link(fn -> false end)
    [first] = append!(prefix, "source-0", "event-0")
    {:ok, appended} = Agent.start_link(fn -> [first] end)

    # Bounded for the same reason as the writer above: a fixed backlog, not an endless stream
    # racing the whole suite's load.
    writer =
      Task.async(fn ->
        1..300
        |> Stream.take_while(fn _ -> not Agent.get(stop, & &1) end)
        |> Enum.each(fn n ->
          try do
            [event] = append!(prefix, "source-#{rem(n, 5)}", "event-#{n}")
            Agent.update(appended, &[event | &1])
          rescue
            _ -> :ok
          end
        end)
      end)

    wait_until(
      fn ->
        {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
        today in result.dropped
      end,
      30_000
    )

    Agent.update(stop, fn _ -> true end)
    Task.await(writer, 30_000)

    expected = appended |> Agent.get(& &1) |> Enum.map(&Event.message_id/1) |> MapSet.new()
    published = expected |> MapSet.size() |> collect_events() |> Enum.map(&Event.message_id/1) |> MapSet.new()

    assert MapSet.size(expected) > 0
    assert published == expected
  end

  test "the advisory lock strategy restarts seq once retention drops a source's events, the counter does not",
       %{prefix: prefix} do
    today = Date.utc_today()
    start_relay!(prefix)

    append!(prefix, "with-counter", ["one", "two"])
    append!(prefix, "with-advisory-lock", ["one", "two"], strategy: :advisory_lock)
    collect_events(4)

    wait_until(fn ->
      {:ok, result} = Retention.drop_partitions(TestRepo, prefix: prefix, before: Date.add(today, 1))
      today in result.dropped
    end)

    Retention.create_partitions(TestRepo, prefix: prefix, today: today, days_ahead: 0)

    [counter] = append!(prefix, "with-counter", "three")
    [advisory] = append!(prefix, "with-advisory-lock", "three", strategy: :advisory_lock)

    assert counter.position.seq.value == 3
    assert advisory.position.seq.value == 1
  end

  defp attempt_write(prefix, n) do
    append!(prefix, "writer", "during-retention-#{n}")
    :ok
  rescue
    _ -> :no_partition
  end

  defp lock_partition!(prefix, day) do
    SQL.query!(TestRepo, ~s(LOCK TABLE #{partition_table(prefix, day)} IN ROW EXCLUSIVE MODE))
  end

  defp detaching?(prefix, day) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT 1 FROM pg_stat_activity
         WHERE datname = current_database()
           AND wait_event_type = 'Lock'
           AND query ILIKE '%DETACH PARTITION ' || $1 || '%'
        """,
        [partition_table(prefix, day)]
      )

    rows != []
  end

  defp events_tuples(prefix) do
    TestRepo
    |> Retention.partitions(prefix: prefix)
    |> Enum.map(&partition_tuples(prefix, &1))
    |> Enum.reduce(%{live: 0, dead: 0}, &%{live: &1.live + &2.live, dead: &1.dead + &2.dead})
  end

  defp partition_tuples(prefix, day) do
    table = partition_table(prefix, day)

    %Postgrex.Result{rows: [[live, dead]]} =
      SQL.query!(TestRepo, "SELECT tuple_count, dead_tuple_count FROM pgstattuple($1::text::regclass)", [table])

    %{live: live, dead: dead}
  end

  defp partition_table(prefix, day), do: ~s("#{prefix}"."outbox_events_#{Calendar.strftime(day, "%Y%m%d")}")

  defp event_count(prefix) do
    %Postgrex.Result{rows: [[count]]} = SQL.query!(TestRepo, ~s|SELECT count(*) FROM "#{prefix}".outbox_events|)
    count
  end

  defp table_stats(prefix, table) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        "SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE schemaname = $1 AND relname = $2",
        [prefix, table]
      )

    case rows do
      [[updates, hot_updates]] -> {updates, hot_updates}
      [] -> {0, 0}
    end
  end

  defp stats_delta_until(prefix, table, {updates_before, hot_before}, expected, timeout \\ 15_000) do
    {updates, hot_updates} =
      wait_until(
        fn ->
          {updates, _hot_updates} = stats = table_stats(prefix, table)
          if updates - updates_before >= expected, do: stats
        end,
        timeout
      )

    {updates - updates_before, hot_updates - hot_before}
  end

  defp xact_tuple_stats(prefix, table) do
    %Postgrex.Result{rows: [[updated, hot_updated]]} =
      SQL.query!(
        TestRepo,
        """
        SELECT pg_stat_get_xact_tuples_updated(c.oid), pg_stat_get_xact_tuples_hot_updated(c.oid)
          FROM pg_class c
         WHERE c.oid = $1::text::regclass
        """,
        [Postgres.name(prefix, table)]
      )

    {updated, hot_updated}
  end

  # The number of in-place updates guaranteed to stay heap-only tuple updates with zero page
  # pruning: the free space a page keeps reserved below its fillfactor, divided by the size one
  # more tuple version takes. Pruning (and whether it succeeds) depends on the cluster-wide vacuum
  # horizon, which this test does not control, so staying under this count is what makes every
  # update HOT regardless of what else is running on the shared instance.
  defp max_hot_updates(prefix, table) do
    free_bytes = block_size() * (100 - fillfactor(prefix, table)) / 100
    line_pointer_size = 4

    trunc(free_bytes / (avg_tuple_len(prefix, table) + line_pointer_size))
  end

  defp block_size do
    %Postgrex.Result{rows: [[size]]} = SQL.query!(TestRepo, "SELECT current_setting('block_size')::int", [])
    size
  end

  defp fillfactor(prefix, table) do
    %Postgrex.Result{rows: [[reloptions]]} =
      SQL.query!(TestRepo, "SELECT reloptions FROM pg_class WHERE oid = $1::text::regclass", [
        Postgres.name(prefix, table)
      ])

    reloptions
    |> List.wrap()
    |> Enum.find_value(100, fn option ->
      case String.split(option, "=") do
        ["fillfactor", value] -> String.to_integer(value)
        _not_fillfactor -> nil
      end
    end)
  end

  defp avg_tuple_len(prefix, table) do
    %Postgrex.Result{rows: [[tuple_len, tuple_count]]} =
      SQL.query!(TestRepo, "SELECT tuple_len, tuple_count FROM pgstattuple($1::text::regclass)", [
        Postgres.name(prefix, table)
      ])

    tuple_len / tuple_count
  end

  defp indexed_columns(prefix, table) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT a.attname
          FROM pg_index i
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
         WHERE i.indrelid = $1::text::regclass
        """,
        [Postgres.name(prefix, table)]
      )

    Enum.map(rows, fn [name] -> name end)
  end

  defp assert_fillfactor(prefix, table, expected), do: assert(fillfactor(prefix, table) == expected)

  defp assert_no_index_on(prefix, table, columns) do
    assert indexed_columns(prefix, table) -- columns == indexed_columns(prefix, table)
  end
end
