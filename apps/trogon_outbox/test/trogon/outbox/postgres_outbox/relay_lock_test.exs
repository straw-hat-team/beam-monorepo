defmodule Trogon.Outbox.PostgresOutbox.RelayLockTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  import Bitwise

  alias Trogon.Outbox.{Batch, LockNamespace, Partition, Relay}

  test "a second relay with the same name cannot take a partition that is held", %{prefix: prefix} do
    holder = start_relay!(prefix, tag: :holder)
    wait_until(fn -> length(Relay.held_partitions(holder)) == 8 end)

    standby = start_relay!(prefix, tag: :standby)

    # A fixed sleep here before checking standby's held partitions is a guess at how long it takes
    # the standby to retry its lock_interval at least once, and a guess that holds under light load
    # can fall short under a full suite run's contention. Appending and collecting events below
    # takes its own real time regardless of load, which is already enough for the standby's own
    # retries to run several times over, so there is nothing left to wait for separately.
    Enum.each(1..10, &append!(prefix, "source-#{&1}", "event-#{&1}"))
    events = collect_events(10)

    assert length(events) == 10
    refute_received {:published, :standby, _batch}
    assert Relay.held_partitions(holder) == Partition.all(8)
    assert Relay.held_partitions(standby) == []
  end

  test "a standby takes over every partition once the holder's backend is terminated", %{prefix: prefix} do
    holder = start_relay!(prefix, tag: :holder, restart: :temporary)
    wait_until(fn -> length(Relay.held_partitions(holder)) == 8 end)

    standby = start_relay!(prefix, tag: :standby)
    append!(prefix, "source-a", "before")
    assert_receive {:published, :holder, %Batch{partition: partition, events: [%{payload: "before"} = before]}}, 10_000
    wait_until(fn -> cursor_row(prefix, "test", partition.value) == {before.cursor.xid, before.cursor.id} end)

    holder_ref = Process.monitor(holder)
    [backend_pid] = relay_backend_pids()
    assert SQL.query!(TestRepo, "SELECT pg_terminate_backend($1)", [backend_pid]).rows == [[true]]

    assert_receive {:DOWN, ^holder_ref, :process, _pid, _reason}, 10_000
    wait_until(fn -> length(Relay.held_partitions(standby)) == 8 end)

    append!(prefix, "source-a", "after")
    assert_receive {:published, :standby, %Batch{events: [%{payload: "after"} = after_event]}}, 10_000
    refute_receive {:published, _tag, _batch}, 300

    assert after_event.position.seq.value == 2
    assert relay_backend_pids() != [backend_pid]
  end

  test "the writer lock does not collide with a single-bigint advisory lock of the same bits", %{prefix: prefix} do
    %Postgrex.Result{rows: [[objid]]} = SQL.query!(TestRepo, "SELECT hashtext('source-a')")
    same_bits = LockNamespace.writer() <<< 32 ||| (objid &&& 0xFFFFFFFF)

    single_bigint_holder = open_transaction()
    run_in(single_bigint_holder, fn -> SQL.query!(TestRepo, "SELECT pg_advisory_xact_lock($1)", [same_bits]) end)

    appender =
      Task.async(fn -> append!(prefix, "source-a", "not blocked", strategy: :advisory_lock) end)

    assert [%{payload: "not blocked"}] = Task.await(appender, 2_000)

    %Postgrex.Result{rows: locks} =
      SQL.query!(
        TestRepo,
        """
        SELECT classid::bigint, objid::bigint, objsubid FROM pg_locks
         WHERE locktype = 'advisory' AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        """
      )

    assert [LockNamespace.writer(), objid &&& 0xFFFFFFFF, 1] in locks

    finish(single_bigint_holder)
  end

  test "the writer lock does block a two-integer lock in the same namespace", %{prefix: prefix} do
    holder = open_transaction()

    run_in(holder, fn ->
      SQL.query!(TestRepo, "SELECT pg_advisory_xact_lock($1::int, hashtext('source-a'))", [LockNamespace.writer()])
    end)

    appender = Task.async(fn -> append!(prefix, "source-a", "waited", strategy: :advisory_lock) end)
    assert Task.yield(appender, 500) == nil

    finish(holder)
    assert [%{payload: "waited"}] = Task.await(appender, 5_000)
  end

  test "two relay names whose hashtext collided under the old scheme no longer share a lock", %{prefix: prefix} do
    {name_a, name_b} = find_hashtext_collision!(prefix, 0)
    assert old_lock_hash(prefix, name_a, 0) == old_lock_hash(prefix, name_b, 0)

    holder = start_relay!(prefix, relay: name_a, tag: :holder, partitions: [0])
    wait_until(fn -> Relay.held_partitions(holder) == [Partition.new!(0)] end)

    other = start_relay!(prefix, relay: name_b, tag: :other, partitions: [0])
    wait_until(fn -> Relay.held_partitions(other) == [Partition.new!(0)] end)

    id_a = relay_id(prefix, name_a)
    id_b = relay_id(prefix, name_b)

    assert id_a != id_b
    assert Relay.Store.lock_objid(id_a, 0) != Relay.Store.lock_objid(id_b, 0)
  end

  defp relay_id(prefix, relay) do
    %Postgrex.Result{rows: [[id]]} =
      SQL.query!(TestRepo, ~s(SELECT id FROM "#{prefix}".outbox_relays WHERE relay = $1), [relay])

    id
  end

  defp find_hashtext_collision!(prefix, partition) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT names[1], names[2]
          FROM (
            SELECT array_agg(name ORDER BY name) AS names
              FROM (
                SELECT hashtext($1 || ':relay-' || i || ':' || $2) AS h, 'relay-' || i AS name
                  FROM generate_series(1, 1_000_000) AS i
              ) candidates
             GROUP BY h
            HAVING count(*) > 1
          ) collided
         LIMIT 1
        """,
        [prefix, Integer.to_string(partition)]
      )

    case rows do
      [[name_a, name_b]] -> {name_a, name_b}
      [] -> flunk("no hashtext collision found among 1000000 candidates for prefix #{prefix}")
    end
  end

  defp old_lock_hash(prefix, relay, partition) do
    %Postgrex.Result{rows: [[hash]]} =
      SQL.query!(TestRepo, "SELECT hashtext($1 || ':' || $2 || ':' || $3)", [
        prefix,
        relay,
        Integer.to_string(partition)
      ])

    hash
  end

  defp relay_backend_pids do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT DISTINCT l.pid FROM pg_locks l
          JOIN pg_database d ON d.oid = l.database
         WHERE l.locktype = 'advisory' AND l.classid::bigint = $1 AND l.objsubid = 2 AND l.granted
           AND d.datname = current_database()
        """,
        [LockNamespace.relay()]
      )

    List.flatten(rows)
  end
end
