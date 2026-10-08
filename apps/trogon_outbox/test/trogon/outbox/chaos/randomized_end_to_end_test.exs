defmodule Trogon.Outbox.Chaos.RandomizedEndToEndTest do
  @moduledoc """
  Drives concurrent writers, random relay kills, backend terminations, savepoint rollbacks, and a
  flaky publisher at once, then checks the invariants a relay promises: gapless seq per source,
  per-source publish order, nothing lost, and duplicates only sharing the same message id.

  Every run is seeded and the seed is printed, so a failure can be replayed with the same seed.
  Real concurrency and OS scheduling still make exact byte-for-byte replay unlikely; the seed
  reproduces the same sequence of decisions in each process, not the same interleaving between
  them.
  """

  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Batch, Event, LockNamespace}
  alias Trogon.Outbox.TestSupport.{FlakyPublisher, SequenceGapDetector}

  test "a short deterministic chaos run holds every invariant", %{prefix: prefix} do
    seed = seed_from_env("TROGON_OUTBOX_CHAOS_SMOKE_SEED", 424_242)

    report =
      run_scenario(prefix,
        seed: seed,
        label: "chaos smoke",
        source_count: 10,
        writer_count: 20,
        appends_per_writer: 3,
        rollback_rate: 0.25,
        kill_count: 1,
        kill_interval: 5..15,
        failure_rate: 0.3,
        max_failures: 2,
        collect_timeout: 15_000,
        writer_timeout: 15_000
      )

    assert report.received_batches > 0
  end

  @tag :chaos
  @tag partitions: 16
  @tag timeout: 120_000
  test "a long randomized chaos run holds every invariant across kills, backend terminations, savepoints, and a flaky publisher",
       %{prefix: prefix} do
    seed = seed_from_env("TROGON_OUTBOX_CHAOS_SEED", System.system_time(:microsecond))

    report =
      run_scenario(prefix,
        seed: seed,
        label: "chaos heavy",
        source_count: 50,
        writer_count: 100,
        appends_per_writer: 5,
        rollback_rate: 0.2,
        jitter_ms: 4,
        kill_count: 8,
        kill_interval: 30..150,
        failure_rate: 0.35,
        max_failures: 3,
        collect_timeout: 60_000,
        writer_timeout: 60_000
      )

    assert report.received_batches > 0
  end

  defp seed_from_env(var, default) do
    case System.get_env(var) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp run_scenario(prefix, opts) do
    seed = Keyword.fetch!(opts, :seed)
    label = Keyword.fetch!(opts, :label)
    :rand.seed(:exsss, {seed, seed, seed})
    IO.puts("[#{label}] seed=#{seed}")

    test_pid = self()
    {:ok, counter} = Agent.start_link(fn -> %{} end)
    relay_name = :"chaos_relay_#{System.unique_integer([:positive])}"

    start_relay!(prefix,
      name: relay_name,
      publisher:
        {FlakyPublisher,
         seed: seed,
         failure_rate: Keyword.get(opts, :failure_rate, 0.3),
         max_failures: Keyword.get(opts, :max_failures, 3),
         counter: counter,
         on_publish: fn batch -> send(test_pid, {:published, :chaos, batch}) end}
    )

    chaos_task = run_chaos_driver(relay_name, seed, opts)
    outcomes = run_writers(prefix, seed, opts)
    await_chaos_driver(chaos_task)

    committed = for {:committed, event} <- outcomes, do: event
    rolled_back_payloads = for {:rolled_back, _source, payload} <- outcomes, do: payload
    expected_ids = MapSet.new(committed, &to_string(Event.message_id(&1)))

    received = collect_published(expected_ids, Keyword.get(opts, :collect_timeout, 30_000), seed)

    verify_invariants!(prefix, seed, committed, rolled_back_payloads, received)

    IO.puts(
      "[#{label}] seed=#{seed} committed=#{length(committed)} rolled_back=#{length(rolled_back_payloads)} " <>
        "received=#{length(received)}"
    )

    %{
      seed: seed,
      committed: length(committed),
      rolled_back: length(rolled_back_payloads),
      received_batches: length(received)
    }
  end

  defp run_writers(prefix, seed, opts) do
    source_count = Keyword.fetch!(opts, :source_count)
    writer_count = Keyword.fetch!(opts, :writer_count)
    appends_per_writer = Keyword.fetch!(opts, :appends_per_writer)
    rollback_rate = Keyword.get(opts, :rollback_rate, 0.2)
    jitter_ms = Keyword.get(opts, :jitter_ms, 0)
    sources = Enum.map(1..source_count, &"chaos-source-#{&1}")

    1..writer_count
    |> Task.async_stream(
      fn n ->
        :rand.seed(:exsss, {seed, n, 0})
        source = Enum.at(sources, rem(n, source_count))

        Enum.map(1..appends_per_writer, fn i ->
          if jitter_ms > 0, do: Process.sleep(:rand.uniform(jitter_ms))
          rollback? = :rand.uniform() < rollback_rate
          payload = if rollback?, do: "w#{n}-#{i}-rb", else: "w#{n}-#{i}"
          write_one(prefix, source, payload, rollback?)
        end)
      end,
      max_concurrency: Keyword.get(opts, :writer_concurrency, 6),
      timeout: Keyword.get(opts, :writer_timeout, 30_000)
    )
    |> Enum.flat_map(fn {:ok, results} -> results end)
  end

  defp write_one(prefix, source, payload, rollback?) do
    {:ok, outcome} =
      TestRepo.transaction(fn ->
        SQL.query!(TestRepo, "SAVEPOINT chaos_savepoint")
        {:ok, [event]} = Trogon.Outbox.append(TestRepo, source, payload, prefix: prefix)

        if rollback? do
          SQL.query!(TestRepo, "ROLLBACK TO SAVEPOINT chaos_savepoint")
          {:rolled_back, source, payload}
        else
          SQL.query!(TestRepo, "RELEASE SAVEPOINT chaos_savepoint")
          {:committed, event}
        end
      end)

    outcome
  end

  defp run_chaos_driver(relay_name, seed, opts) do
    case Keyword.get(opts, :kill_count, 0) do
      0 ->
        nil

      kill_count ->
        interval = Keyword.get(opts, :kill_interval, 10..50)

        Task.async(fn ->
          :rand.seed(:exsss, {seed, 1, 1})
          Enum.each(1..kill_count, fn i -> kill_relay!(relay_name, interval, i) end)
        end)
    end
  end

  defp await_chaos_driver(nil), do: :ok
  defp await_chaos_driver(task), do: Task.await(task, 30_000)

  defp kill_relay!(relay_name, interval, i) do
    Process.sleep(Enum.random(interval))

    case Process.whereis(relay_name) do
      nil -> :ok
      pid -> if rem(i, 2) == 0, do: Process.exit(pid, :kill), else: terminate_relay_backend!()
    end

    wait_until(fn ->
      case Process.whereis(relay_name) do
        nil -> false
        pid -> Process.alive?(pid)
      end
    end)
  end

  defp terminate_relay_backend! do
    case relay_backend_pids() do
      [] -> :ok
      pids -> SQL.query!(TestRepo, "SELECT pg_terminate_backend($1)", [Enum.random(pids)])
    end
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

  defp collect_published(expected_ids, timeout, seed) do
    deadline = System.monotonic_time(:millisecond) + timeout
    events = await_expected(expected_ids, MapSet.new(), [], deadline, seed)
    drain_quiet(events)
  end

  defp await_expected(expected_ids, seen, events, deadline, seed) do
    if MapSet.subset?(expected_ids, seen) do
      events
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:published, _tag, %Batch{events: batch}} ->
          ids = MapSet.new(batch, &to_string(Event.message_id(&1)))
          await_expected(expected_ids, MapSet.union(seen, ids), events ++ batch, deadline, seed)
      after
        remaining ->
          missing = MapSet.difference(expected_ids, seen)

          flunk("""
          chaos run with seed #{seed} lost events: #{MapSet.size(missing)} of #{MapSet.size(expected_ids)} \
          committed message ids were never published.
          missing: #{inspect(Enum.take(MapSet.to_list(missing), 20))}
          """)
      end
    end
  end

  defp drain_quiet(events, quiet \\ 300) do
    receive do
      {:published, _tag, %Batch{events: batch}} -> drain_quiet(events ++ batch, quiet)
    after
      quiet -> events
    end
  end

  defp verify_invariants!(prefix, seed, committed, rolled_back_payloads, received) do
    verify_nothing_lost_or_corrupted!(seed, committed, received)
    verify_gapless_seq!(seed, committed)
    verify_publish_order!(seed, received)
    verify_duplicates_share_message_id!(seed, received)
    verify_rollback_leaves_nothing!(prefix, seed, rolled_back_payloads)
  end

  defp verify_nothing_lost_or_corrupted!(seed, committed, received) do
    expected_ids = MapSet.new(committed, &to_string(Event.message_id(&1)))
    received_ids = MapSet.new(received, &to_string(Event.message_id(&1)))

    unless MapSet.equal?(received_ids, expected_ids) do
      flunk(
        invariant_failure_message(seed, "published message ids do not match committed message ids", %{
          missing: expected_ids |> MapSet.difference(received_ids) |> MapSet.to_list() |> Enum.take(20),
          unexpected: received_ids |> MapSet.difference(expected_ids) |> MapSet.to_list() |> Enum.take(20)
        })
      )
    end
  end

  defp verify_gapless_seq!(seed, committed) do
    committed
    |> Enum.group_by(& &1.position.source.value, & &1.position.seq.value)
    |> Enum.each(fn {source, seqs} ->
      sorted = Enum.sort(seqs)
      expected = Enum.to_list(1..length(seqs))

      unless sorted == expected do
        flunk(
          invariant_failure_message(seed, "source #{source} has a gap in its committed seq", %{
            source: source,
            seqs: sorted,
            missing: SequenceGapDetector.missing(seqs)
          })
        )
      end
    end)
  end

  defp verify_publish_order!(seed, received) do
    received
    |> Enum.group_by(& &1.position.source.value)
    |> Enum.each(fn {source, events} ->
      seqs =
        events
        |> Enum.uniq_by(&to_string(Event.message_id(&1)))
        |> Enum.map(& &1.position.seq.value)

      non_decreasing? = seqs |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> a <= b end)

      unless non_decreasing? do
        flunk(
          invariant_failure_message(seed, "source #{source} was published out of seq order", %{
            source: source,
            first_occurrence_seqs: seqs
          })
        )
      end
    end)
  end

  defp verify_duplicates_share_message_id!(seed, received) do
    received
    |> Enum.group_by(&to_string(Event.message_id(&1)))
    |> Enum.each(fn {message_id, events} ->
      payloads = events |> Enum.map(& &1.payload) |> Enum.uniq()

      unless length(payloads) == 1 do
        flunk(
          invariant_failure_message(seed, "events sharing message id #{message_id} disagree on payload", %{
            message_id: message_id,
            payloads: payloads
          })
        )
      end
    end)
  end

  defp verify_rollback_leaves_nothing!(prefix, seed, rolled_back_payloads) do
    %Postgrex.Result{rows: rows} = SQL.query!(TestRepo, ~s(SELECT payload FROM "#{prefix}".outbox_events))
    stored = MapSet.new(List.flatten(rows))
    leaked = MapSet.intersection(stored, MapSet.new(rolled_back_payloads))

    unless MapSet.size(leaked) == 0 do
      flunk(
        invariant_failure_message(seed, "a savepoint rollback left rows behind", %{
          leaked: MapSet.to_list(leaked)
        })
      )
    end
  end

  defp invariant_failure_message(seed, summary, state) do
    "chaos invariant violated (seed=#{seed}): #{summary}\nstate: #{inspect(state, limit: :infinity, pretty: true)}"
  end
end
