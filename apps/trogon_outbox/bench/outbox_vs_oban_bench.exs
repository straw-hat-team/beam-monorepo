# Head-to-head: Trogon.Outbox.Relay against a minimal Oban OSS relay, same container, same run.
#
#     TROGON_OUTBOX_BENCH_DATABASE_URL=ecto://postgres:postgres@trogon-outbox-pg.orb.local:5432/trogon_outbox_bench \
#       MIX_ENV=test mix run bench/outbox_vs_oban_bench.exs
#
# Builds on bench/outbox_bench.exs (our own write+relay+end-to-end benchmark) and
# bench/oban_relay_bench.exs (Oban's own Basic engine fetch cost under backlog and large args).
# Neither of those measurements is repeated here: this file only adds the side-by-side sustained
# run and the table bloat comparison. Both relays run back to back against the same
# trogon-outbox-pg container under the same prefix-per-run isolation outbox_bench.exs and
# oban_relay_bench.exs already use, so hardware is identical. Connections on both sides disable
# Nagle's algorithm for the same reason noted in both benches: some local Docker networks add a
# fixed 200ms stall to multi-packet replies that would otherwise swamp the numbers.
#
# TROGON_OUTBOX_BENCH_SECONDS sets how long writers push events before the run drains, 10 by
# default. TROGON_OUTBOX_BENCH_WRITERS sets writer concurrency, 8 by default, matching
# outbox_bench.exs's own end_to_end scenario (8 writers, distinct sources).
#
# The Oban side runs a real queue (testing: :disabled) with Oban's default Basic engine and
# Database peer. Its queue concurrency (TROGON_OUTBOX_BENCH_OBAN_CONCURRENCY,
# 20 by default) and our relay's batch size are each the kind of system the two projects ship by
# default, not a tuned-to-match pair: our relay is one process reading batches of up to
# :batch_size events per partition per poll, Oban runs up to the queue's local_limit jobs
# concurrently per node. Comparing them is still useful, just not apples to apples on concurrency
# model.

defmodule Trogon.Outbox.RaceBench.Repo do
  use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
end

defmodule Trogon.Outbox.RaceBench.OutboxMigration do
  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(prefix: "race_outbox", partitions: 64)
  def down, do: Trogon.Outbox.Migration.down(prefix: "race_outbox")
end

defmodule Trogon.Outbox.RaceBench.ObanMigration do
  use Ecto.Migration

  def up, do: Oban.Migration.up(prefix: "race_oban")
  def down, do: Oban.Migration.down(prefix: "race_oban")
end

defmodule Trogon.Outbox.RaceBench.CountingPublisher do
  @behaviour Trogon.Outbox.Publisher

  @impl true
  def publish(batch, _opts) do
    now = System.monotonic_time(:microsecond)
    send(:race_bench_collector, {:published, now, Enum.map(batch.events, & &1.payload)})
    :ok
  end
end

defmodule Trogon.Outbox.RaceBench.PublishWorker do
  use Oban.Worker, queue: :relay, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ts" => ts}}) do
    now = System.monotonic_time(:microsecond)
    send(:race_bench_collector, {:published, now, [ts]})
    :ok
  end
end

defmodule Trogon.Outbox.RaceBench do
  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.RaceBench.{CountingPublisher, ObanMigration, OutboxMigration, PublishWorker, Repo}

  @outbox_prefix "race_outbox"
  @oban_prefix "race_oban"
  @oban_name :race_oban

  def run do
    url =
      System.get_env(
        "TROGON_OUTBOX_BENCH_DATABASE_URL",
        "ecto://postgres:postgres@trogon-outbox-pg.orb.local:5432/trogon_outbox_bench"
      )

    seconds = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_SECONDS", "10"))
    writers = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_WRITERS", "8"))
    oban_concurrency = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_OBAN_CONCURRENCY", "20"))

    Application.put_env(:trogon_outbox, Repo,
      url: url,
      pool_size: writers + 20,
      queue_target: 5_000,
      log: false,
      timeout: :infinity,
      socket_options: [nodelay: true]
    )

    Logger.configure(level: :warning)

    case Ecto.Adapters.Postgres.storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
    end

    {:ok, _pid} = Repo.start_link()
    Process.register(self(), :race_bench_collector)

    reinstall_outbox!()
    reinstall_oban!()

    %Postgrex.Result{rows: [[version]]} = SQL.query!(Repo, "SHOW server_version")

    IO.puts(
      "Postgres #{version}, #{writers} writers on distinct sources, #{seconds}s of writing " <>
        "before drain, Oban queue concurrency #{oban_concurrency}\n"
    )

    outbox_before = stats!(@outbox_prefix, "outbox_events")
    outbox_result = run_outbox(writers, seconds)
    outbox_after = stats!(@outbox_prefix, "outbox_events")
    outbox_vacuumed = vacuum_and_stats!(@outbox_prefix, "outbox_events")
    cursors_after = stats!(@outbox_prefix, "outbox_cursors")

    oban_before = stats!(@oban_prefix, "oban_jobs")
    oban_result = run_oban(writers, seconds, oban_concurrency)
    oban_after = stats!(@oban_prefix, "oban_jobs")
    oban_vacuumed = vacuum_and_stats!(@oban_prefix, "oban_jobs")

    report(outbox_result, oban_result)
    report_bloat(outbox_before, outbox_after, outbox_vacuumed, oban_before, oban_after, oban_vacuumed, cursors_after)
  end

  defp run_outbox(writers, seconds) do
    {:ok, relay} =
      Trogon.Outbox.Relay.start_link(
        repo: Repo,
        prefix: @outbox_prefix,
        relay: "race",
        batch_size: 500,
        min_poll_interval: 5,
        max_poll_interval: 200,
        publisher: CountingPublisher,
        connection: [socket_options: [nodelay: true]]
      )

    started = System.monotonic_time(:microsecond)
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000

    writer_tasks =
      Enum.map(1..writers, fn writer ->
        Task.async(fn -> outbox_write_loop("source-#{writer}", deadline, 0) end)
      end)

    count = writer_tasks |> Task.await_many(:infinity) |> Enum.sum()
    latencies = drain_latencies(count, [])
    elapsed = (System.monotonic_time(:microsecond) - started) / 1_000_000
    GenServer.stop(relay)

    summarize("outbox relay", count, elapsed, latencies)
  end

  defp outbox_write_loop(source, deadline, count) do
    if System.monotonic_time(:millisecond) >= deadline do
      count
    else
      payload = Integer.to_string(System.monotonic_time(:microsecond))

      {:ok, _events} =
        Repo.transaction(fn ->
          {:ok, events} = Trogon.Outbox.append(Repo, source, payload, prefix: @outbox_prefix)
          events
        end)

      outbox_write_loop(source, deadline, count + 1)
    end
  end

  defp run_oban(writers, seconds, concurrency) do
    {:ok, oban} =
      Oban.start_link(
        name: @oban_name,
        repo: Repo,
        prefix: @oban_prefix,
        testing: :disabled,
        stager: [interval: 50],
        queues: [relay: concurrency],
        shutdown_grace_period: 2_000
      )

    started = System.monotonic_time(:microsecond)
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000

    writer_tasks =
      Enum.map(1..writers, fn _writer ->
        Task.async(fn -> oban_write_loop(deadline, 0) end)
      end)

    count = writer_tasks |> Task.await_many(:infinity) |> Enum.sum()
    latencies = drain_latencies(count, [])
    elapsed = (System.monotonic_time(:microsecond) - started) / 1_000_000
    :ok = Supervisor.stop(oban)

    summarize("Oban OSS relay", count, elapsed, latencies)
  end

  defp oban_write_loop(deadline, count) do
    if System.monotonic_time(:millisecond) >= deadline do
      count
    else
      ts = Integer.to_string(System.monotonic_time(:microsecond))
      {:ok, %Oban.Job{}} = Oban.insert(@oban_name, PublishWorker.new(%{"ts" => ts}))
      oban_write_loop(deadline, count + 1)
    end
  end

  defp drain_latencies(0, latencies), do: latencies

  defp drain_latencies(remaining, latencies) do
    receive do
      {:published, now, payloads} ->
        batch = Enum.map(payloads, &(now - String.to_integer(&1)))
        drain_latencies(remaining - length(payloads), batch ++ latencies)
    after
      60_000 -> raise "the relay stopped publishing with #{remaining} events left"
    end
  end

  defp summarize(label, count, elapsed_seconds, latencies) do
    sorted = Enum.sort(latencies)

    %{
      label: label,
      count: count,
      elapsed: elapsed_seconds,
      throughput: count / elapsed_seconds,
      p50: percentile(sorted, 0.50),
      p99: percentile(sorted, 0.99),
      max: List.last(sorted) || 0
    }
  end

  defp report(outbox_result, oban_result) do
    IO.puts("| relay | events | run seconds | events/s | p50 ms | p99 ms | max ms |")
    IO.puts("| --- | --- | --- | --- | --- | --- | --- |")

    for result <- [outbox_result, oban_result] do
      IO.puts(
        "| #{result.label} | #{result.count} | #{Float.round(result.elapsed, 2)} | " <>
          "#{round(result.throughput)} | #{fmt(result.p50)} | #{fmt(result.p99)} | #{fmt(result.max)} |"
      )
    end

    IO.puts("")
  end

  defp report_bloat(outbox_before, outbox_after, outbox_vacuumed, oban_before, oban_after, oban_vacuumed, cursors_after) do
    IO.puts(
      "| table | n_dead_tup before | n_dead_tup after | n_dead_tup after VACUUM | size before | size after | size after VACUUM |"
    )

    IO.puts("| --- | --- | --- | --- | --- | --- | --- |")
    bloat_row("race_outbox.outbox_events", outbox_before, outbox_after, outbox_vacuumed)
    bloat_row("race_oban.oban_jobs", oban_before, oban_after, oban_vacuumed)
    IO.puts("")

    {cursors_dead, cursors_bytes} = cursors_after
    IO.puts("race_outbox.outbox_cursors after the outbox run: #{cursors_dead} dead tuples, #{bytes(cursors_bytes)}.")
  end

  defp bloat_row(name, {dead_before, bytes_before}, {dead_after, bytes_after}, {dead_vacuumed, bytes_vacuumed}) do
    IO.puts(
      "| #{name} | #{dead_before} | #{dead_after} | #{dead_vacuumed} | " <>
        "#{bytes(bytes_before)} | #{bytes(bytes_after)} | #{bytes(bytes_vacuumed)} |"
    )
  end

  defp bytes(value), do: "#{Float.round(value / 1_048_576, 2)} MiB"

  defp stats!(prefix, table) do
    %Postgrex.Result{rows: [[bytes, dead]]} =
      SQL.query!(
        Repo,
        """
        SELECT
          pg_total_relation_size(format('%I.%I', $1::text, $2::text)::regclass),
          coalesce((SELECT n_dead_tup FROM pg_stat_user_tables WHERE schemaname = $1::text AND relname = $2::text), 0)
        """,
        [prefix, table]
      )

    {dead, bytes}
  end

  defp vacuum_and_stats!(prefix, table) do
    SQL.query!(Repo, "VACUUM #{Trogon.Outbox.Postgres.name(prefix, table)}")
    stats!(prefix, table)
  end

  defp reinstall_outbox! do
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{@outbox_prefix} CASCADE")
    SQL.query!(Repo, "CREATE SCHEMA #{@outbox_prefix}")
    Ecto.Migrator.run(Repo, [{1, OutboxMigration}], :up, all: true, prefix: @outbox_prefix, log: false)
  end

  defp reinstall_oban! do
    Ecto.Migrator.run(Repo, [{1, ObanMigration}], :down, all: true, log: false)
    Ecto.Migrator.run(Repo, [{1, ObanMigration}], :up, all: true, log: false)
  end

  defp percentile([], _p), do: 0
  defp percentile(sorted, p), do: Enum.at(sorted, min(round(p * (length(sorted) - 1)), length(sorted) - 1))

  defp fmt(microseconds), do: :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
end

Trogon.Outbox.RaceBench.run()
