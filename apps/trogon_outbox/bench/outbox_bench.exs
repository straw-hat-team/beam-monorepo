# Compares the outbox write strategies and measures the relay.
#
#     TROGON_OUTBOX_BENCH_DATABASE_URL=ecto://postgres:postgres@localhost:5432/trogon_outbox_bench \
#       MIX_ENV=test mix run bench/outbox_bench.exs
#
# TROGON_OUTBOX_BENCH_SECONDS sets the duration of each write run, 5 by default.
# TROGON_OUTBOX_BENCH_POOL_SIZE sets the connection pool, 70 by default. Writers above the pool
# size queue for a connection, so keep it above the largest writer count when the server allows.
# TROGON_OUTBOX_BENCH_SYNCHRONOUS_COMMIT=off takes the WAL flush out of commit latency, which
# isolates the cost of each strategy from the disk.

defmodule Trogon.Outbox.Bench.Repo do
  use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
end

defmodule Trogon.Outbox.Bench.Migration do
  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(prefix: prefix(), partitions: 64)
  def down, do: Trogon.Outbox.Migration.down(prefix: prefix())
end

defmodule Trogon.Outbox.Bench.CountingPublisher do
  @behaviour Trogon.Outbox.Publisher

  @impl true
  def publish(batch, opts) do
    now = System.monotonic_time(:microsecond)
    send(Keyword.fetch!(opts, :collector), {:published, now, batch.events})
    :ok
  end
end

defmodule Trogon.Outbox.Bench do
  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.Bench.{CountingPublisher, Migration, Repo}

  @prefix "outbox_bench"
  @payload :binary.copy("x", 200)

  def run do
    url =
      System.get_env("TROGON_OUTBOX_BENCH_DATABASE_URL", "ecto://postgres:postgres@localhost:5432/trogon_outbox_bench")

    seconds = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_SECONDS", "5"))
    pool_size = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_POOL_SIZE", "70"))

    synchronous_commit = System.get_env("TROGON_OUTBOX_BENCH_SYNCHRONOUS_COMMIT", "on")

    Application.put_env(:trogon_outbox, Repo,
      url: url,
      pool_size: pool_size,
      queue_target: 5_000,
      log: false,
      parameters: [synchronous_commit: synchronous_commit],
      socket_options: [nodelay: true]
    )

    Logger.configure(level: :warning)

    case Ecto.Adapters.Postgres.storage_up(Repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
    end

    {:ok, _pid} = Repo.start_link()
    reinstall!()

    %Postgrex.Result{rows: [[version]]} = SQL.query!(Repo, "SHOW server_version")

    IO.puts(
      "Postgres #{version}, #{System.schedulers_online()} schedulers, pool of #{pool_size}, " <>
        "synchronous_commit #{synchronous_commit}, #{seconds}s per write run\n"
    )

    IO.puts("| strategy | writers | sources | commits/s | p50 ms | p99 ms |")
    IO.puts("| --- | --- | --- | --- | --- | --- |")

    for strategy <- [:counter, :advisory_lock], writers <- [1, 8, 64], sources <- [:same, :distinct] do
      truncate!()
      {throughput, p50, p99} = write_run(strategy, writers, sources, seconds)
      IO.puts("| #{strategy} | #{writers} | #{sources} | #{round(throughput)} | #{fmt(p50)} | #{fmt(p99)} |")
    end

    IO.puts("")
    relay_throughput()
    IO.puts("")
    end_to_end(seconds)
  end

  defp write_run(strategy, writers, sources, seconds) do
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000
    started = System.monotonic_time(:microsecond)

    latencies =
      1..writers
      |> Enum.map(fn writer ->
        source = if sources == :same, do: "source-0", else: "source-#{writer}"
        Task.async(fn -> write_loop(strategy, source, deadline, []) end)
      end)
      |> Task.await_many(:infinity)
      |> List.flatten()

    elapsed = (System.monotonic_time(:microsecond) - started) / 1_000_000
    sorted = Enum.sort(latencies)
    {length(sorted) / elapsed, percentile(sorted, 0.50), percentile(sorted, 0.99)}
  end

  defp write_loop(strategy, source, deadline, latencies) do
    if System.monotonic_time(:millisecond) >= deadline do
      latencies
    else
      started = System.monotonic_time(:microsecond)

      {:ok, _events} =
        Repo.transaction(fn ->
          {:ok, events} = Trogon.Outbox.append(Repo, source, @payload, prefix: @prefix, strategy: strategy)
          events
        end)

      write_loop(strategy, source, deadline, [System.monotonic_time(:microsecond) - started | latencies])
    end
  end

  defp relay_throughput do
    truncate!()
    total = 100_000

    SQL.query!(
      Repo,
      """
      INSERT INTO #{@prefix}.outbox_events (source, seq, xid, payload)
      SELECT 'source-' || (n % 1000), n / 1000 + 1, pg_current_xact_id(), $1
        FROM generate_series(0, $2 - 1) AS n
      """,
      [@payload, total]
    )

    SQL.query!(Repo, "ANALYZE #{@prefix}.outbox_events")

    IO.puts("| relay batch size | events | seconds | events/s |")
    IO.puts("| --- | --- | --- | --- |")

    for batch_size <- [100, 500, 1_000] do
      SQL.query!(Repo, "TRUNCATE #{@prefix}.outbox_cursors")
      started = System.monotonic_time(:microsecond)
      {:ok, relay} = start_relay(batch_size)
      drain(total)
      elapsed = (System.monotonic_time(:microsecond) - started) / 1_000_000
      GenServer.stop(relay)
      IO.puts("| #{batch_size} | #{total} | #{Float.round(elapsed, 2)} | #{round(total / elapsed)} |")
    end
  end

  defp end_to_end(seconds) do
    truncate!()
    {:ok, relay} = start_relay(500)
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000

    writers =
      Enum.map(1..8, fn writer ->
        Task.async(fn -> timed_write_loop("source-#{writer}", deadline, 0) end)
      end)

    count = writers |> Task.await_many(:infinity) |> Enum.sum()
    latencies = collect_latencies(count, [])
    GenServer.stop(relay)

    sorted = Enum.sort(latencies)

    IO.puts("| end to end, 8 writers, distinct sources | events | p50 ms | p99 ms | max ms |")
    IO.puts("| --- | --- | --- | --- | --- |")

    IO.puts(
      "| append to publish | #{count} | #{fmt(percentile(sorted, 0.5))} | #{fmt(percentile(sorted, 0.99))} | #{fmt(List.last(sorted))} |"
    )
  end

  defp timed_write_loop(source, deadline, count) do
    if System.monotonic_time(:millisecond) >= deadline do
      count
    else
      payload = Integer.to_string(System.monotonic_time(:microsecond))

      {:ok, _events} =
        Repo.transaction(fn ->
          {:ok, events} = Trogon.Outbox.append(Repo, source, payload, prefix: @prefix)
          events
        end)

      Process.sleep(1)
      timed_write_loop(source, deadline, count + 1)
    end
  end

  defp collect_latencies(0, latencies), do: latencies

  defp collect_latencies(remaining, latencies) do
    receive do
      {:published, now, events} ->
        batch = Enum.map(events, &(now - String.to_integer(&1.payload)))
        collect_latencies(remaining - length(events), batch ++ latencies)
    after
      30_000 -> raise "the relay stopped publishing with #{remaining} events left"
    end
  end

  defp start_relay(batch_size) do
    Trogon.Outbox.Relay.start_link(
      repo: Repo,
      prefix: @prefix,
      relay: "bench",
      batch_size: batch_size,
      publisher: {CountingPublisher, collector: self()}
    )
  end

  defp drain(0), do: :ok

  defp drain(remaining) do
    receive do
      {:published, _now, events} -> drain(remaining - length(events))
    after
      30_000 -> raise "the relay stopped publishing with #{remaining} events left"
    end
  end

  defp reinstall! do
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{@prefix} CASCADE")
    SQL.query!(Repo, "CREATE SCHEMA #{@prefix}")
    Ecto.Migrator.run(Repo, [{1, Migration}], :up, all: true, prefix: @prefix, log: false)
  end

  defp truncate! do
    SQL.query!(Repo, "TRUNCATE #{@prefix}.outbox_events, #{@prefix}.outbox_sources, #{@prefix}.outbox_cursors")
  end

  defp percentile([], _p), do: 0
  defp percentile(sorted, p), do: Enum.at(sorted, min(round(p * (length(sorted) - 1)), length(sorted) - 1))

  defp fmt(microseconds), do: :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
end

Trogon.Outbox.Bench.run()
