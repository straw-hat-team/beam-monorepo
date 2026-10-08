defmodule Trogon.Outbox.PostgresOutbox.RelayTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Batch, Relay}

  test "a transaction that appended first but commits last is never skipped", %{prefix: prefix} do
    start_relay!(prefix)

    late = open_transaction()
    run_in(late, fn -> Trogon.Outbox.append(TestRepo, "source-a", "late", prefix: prefix) end)

    append!(prefix, "source-b", "early")
    refute_receive {:published, _tag, _batch}, 500

    finish(late)

    assert prefix |> published_payloads(2) |> Enum.sort() == ["early", "late"]
  end

  test "a rolled-back transaction is never delivered", %{prefix: prefix} do
    start_relay!(prefix)

    rolled_back = open_transaction()
    run_in(rolled_back, fn -> Trogon.Outbox.append(TestRepo, "source-a", "rolled-back", prefix: prefix) end)
    finish(rolled_back, :rollback)

    append!(prefix, "source-a", "committed")

    [event] = collect_events(1)
    refute_receive {:published, _tag, _batch}, 500

    assert event.payload == "committed"
    assert event.position.seq.value == 1
  end

  test "a long open transaction with an xid delays delivery but loses nothing", %{prefix: prefix} do
    start_relay!(prefix)

    long = open_transaction()
    run_in(long, &current_xid!/0)

    Enum.each(1..5, &append!(prefix, "source-#{&1}", "event-#{&1}"))
    refute_receive {:published, _tag, _batch}, 1_000

    finish(long)

    assert prefix |> published_payloads(5) |> Enum.sort() == Enum.map(1..5, &"event-#{&1}")
  end

  test "transaction_timeout armed before the long transaction takes its xid bounds the delay", %{prefix: prefix} do
    relay = start_relay!(prefix)

    long = open_transaction()
    run_in(long, fn -> SQL.query!(TestRepo, "SET transaction_timeout = '300ms'") end)
    run_in(long, &current_xid!/0)

    append!(prefix, "source-a", "after-stuck-transaction")

    # Waiting out a fixed window before checking nothing published only proves the point if the
    # window reliably ends before the 300ms transaction_timeout fires, which is exactly the kind of
    # timing assumption that is flaky under load. Reading the relay's own watermark holdback instead
    # confirms, at this exact instant, that some other transaction (the long one, still open) is
    # still holding the watermark back, which is the actual condition the delay depends on.
    assert Relay.health(relay).watermark_holdback_ms > 0
    refute_received {:published, _tag, _batch}

    assert published_payloads(prefix, 1) == ["after-stuck-transaction"]
  end

  test "a long open read-only transaction does not delay delivery", %{prefix: prefix} do
    start_relay!(prefix)

    read_only = open_transaction()

    run_in(read_only, fn ->
      SQL.query!(TestRepo, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
      SQL.query!(TestRepo, ~s|SELECT count(*) FROM "#{prefix}".outbox_events|)
    end)

    append!(prefix, "source-a", "while-read-only-is-open")

    assert published_payloads(prefix, 1) == ["while-read-only-is-open"]

    finish(read_only)
  end

  test "a relay that crashes after publishing but before advancing replays the exact batch", %{prefix: prefix} do
    test_pid = self()
    partition = Trogon.Outbox.partition_of(TestRepo, "source-a", prefix: prefix)
    appended = append!(prefix, "source-a", ["one", "two", "three"])

    crashing =
      start_relay!(prefix,
        restart: :temporary,
        handler: fn batch ->
          send(test_pid, {:published_before_crash, batch})
          Process.sleep(:infinity)
        end
      )

    assert_receive {:published_before_crash, %Batch{events: before_crash}}, 10_000

    ref = Process.monitor(crashing)
    Process.exit(crashing, :kill)
    assert_receive {:DOWN, ^ref, :process, _pid, :killed}, 5_000

    assert cursor_row(prefix, "test", partition.value) == {0, 0}

    start_relay!(prefix)
    replayed = collect_events(3)

    assert ids(before_crash) == ids(appended)
    assert ids(replayed) == ids(before_crash)
    assert Enum.map(replayed, & &1.payload) == Enum.map(before_crash, & &1.payload)
    wait_until(fn -> cursor_row(prefix, "test", partition.value) == cursor_tuple(List.last(appended)) end)
  end

  test "a publisher error leaves the cursor in place and the same batch is retried", %{prefix: prefix} do
    test_pid = self()
    {:ok, attempts} = Agent.start_link(fn -> 0 end)
    partition = Trogon.Outbox.partition_of(TestRepo, "source-a", prefix: prefix)
    appended = append!(prefix, "source-a", ["one", "two"])

    start_relay!(prefix,
      handler: fn batch ->
        attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
        send(test_pid, {:attempt, attempt, ids(batch.events), cursor_row(prefix, "test", partition.value)})
        if attempt <= 3, do: {:error, :broker_down}, else: :ok
      end
    )

    for attempt <- 1..4 do
      assert_receive {:attempt, ^attempt, batch_ids, cursor}, 10_000
      assert batch_ids == ids(appended)
      assert cursor == {0, 0}
    end

    wait_until(fn -> cursor_row(prefix, "test", partition.value) == cursor_tuple(List.last(appended)) end)
    refute_receive {:attempt, 5, _ids, _cursor}, 300
  end

  @tag partitions: 4
  test "a partition whose publishes keep failing does not hold back the others", %{prefix: prefix} do
    test_pid = self()
    {stuck_source, healthy_sources} = sources_split_by_partition(prefix)
    stuck = Trogon.Outbox.partition_of(TestRepo, stuck_source, prefix: prefix)

    start_relay!(prefix,
      handler: fn batch ->
        if batch.partition == stuck do
          send(test_pid, {:stuck_attempt, batch.partition})
          {:error, :poison}
        else
          send(test_pid, {:published, :healthy, batch})
          :ok
        end
      end
    )

    append!(prefix, stuck_source, "stuck")
    assert_receive {:stuck_attempt, ^stuck}, 10_000

    Enum.each(healthy_sources, &append!(prefix, &1, "healthy"))
    healthy = collect_events(length(healthy_sources))

    assert_receive {:stuck_attempt, ^stuck}, 10_000
    assert Enum.all?(healthy, &(&1.partition != stuck))
    assert Enum.sort(Enum.map(healthy, & &1.position.source.value)) == Enum.sort(healthy_sources)
    assert cursor_row(prefix, "test", stuck.value) == {0, 0}
  end

  test "relays with different names each publish every event", %{prefix: prefix} do
    start_relay!(prefix, relay: "rabbitmq")
    start_relay!(prefix, relay: "audit")

    append!(prefix, "source-a", "shared")

    assert_receive {:published, "rabbitmq", %Batch{events: [%{payload: "shared"}]}}, 10_000
    assert_receive {:published, "audit", %Batch{events: [%{payload: "shared"}]}}, 10_000
  end

  test "polling wakes the relay without waiting for its backoff", %{prefix: prefix} do
    relay = start_relay!(prefix, min_poll_interval: 60_000, max_poll_interval: 60_000)
    wait_until(fn -> Relay.held_partitions(relay) != [] end)

    append!(prefix, "source-a", "woken")
    refute_receive {:published, _tag, _batch}, 300

    assert poll_until_published(relay) == ["woken"]
  end

  defp poll_until_published(relay, attempts \\ 100) do
    Relay.poll(relay)

    receive do
      {:published, _tag, batch} -> Enum.map(batch.events, & &1.payload)
    after
      100 ->
        if attempts > 1, do: poll_until_published(relay, attempts - 1), else: flunk("the relay never published")
    end
  end

  defp published_payloads(_prefix, count), do: count |> collect_events() |> Enum.map(& &1.payload)

  defp cursor_tuple(event), do: {event.cursor.xid, event.cursor.id}

  defp sources_split_by_partition(prefix) do
    [stuck | others] = Enum.map(1..40, &"source-#{&1}")
    stuck_partition = Trogon.Outbox.partition_of(TestRepo, stuck, prefix: prefix)
    healthy = Enum.reject(others, &(Trogon.Outbox.partition_of(TestRepo, &1, prefix: prefix) == stuck_partition))
    {stuck, Enum.take(healthy, 6)}
  end
end
