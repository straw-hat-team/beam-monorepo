# Measures append latency as a transaction accumulates savepoints past the 64 subtransaction XIDs
# Postgres caches in shared memory, and the cost a separate session pays to take a snapshot (what
# the relay's watermark read and Retention.drop_partitions/2's in-flight check both do) while that
# transaction is still open.
#
#     TROGON_OUTBOX_BENCH_DATABASE_URL=ecto://postgres:postgres@localhost:5432/trogon_outbox_bench \
#       MIX_ENV=test mix run bench/subxid_overflow_bench.exs
#
# TROGON_OUTBOX_BENCH_SUBTRANSACTIONS sets how many nested, committed savepoints the writer opens
# in one business transaction, 200 by default, well past the 64 that stay cached.

defmodule Trogon.Outbox.Bench.SubxidRepo do
  use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
end

defmodule Trogon.Outbox.Bench.SubxidMigration do
  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(prefix: prefix(), partitions: 8)
  def down, do: Trogon.Outbox.Migration.down(prefix: prefix())
end

defmodule Trogon.Outbox.Bench.Subxid do
  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.Bench.{SubxidMigration, SubxidRepo}

  @prefix "outbox_bench_subxid"
  @overflow_at 64

  def run do
    url =
      System.get_env("TROGON_OUTBOX_BENCH_DATABASE_URL", "ecto://postgres:postgres@localhost:5432/trogon_outbox_bench")

    subtransactions = String.to_integer(System.get_env("TROGON_OUTBOX_BENCH_SUBTRANSACTIONS", "200"))

    Application.put_env(:trogon_outbox, SubxidRepo, url: url, pool_size: 2, log: false)
    Logger.configure(level: :warning)

    case Ecto.Adapters.Postgres.storage_up(SubxidRepo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
    end

    {:ok, _pid} = SubxidRepo.start_link()
    reinstall!()

    %Postgrex.Result{rows: [[version]]} = SQL.query!(SubxidRepo, "SHOW server_version")
    IO.puts("Postgres #{version}, #{subtransactions} savepoints, overflow past #{@overflow_at}\n")

    {:ok, progress} = Agent.start_link(fn -> 0 end)
    {:ok, snapshots} = Agent.start_link(fn -> [] end)
    {:ok, stop} = Agent.start_link(fn -> false end)

    {:ok, conn} = Postgrex.start_link(Ecto.Repo.Supervisor.parse_url(url))

    snapshotter = Task.async(fn -> snapshot_loop(conn, progress, stop, snapshots) end)

    appends = append_run(subtransactions, progress)

    Agent.update(stop, fn _ -> true end)
    Task.await(snapshotter, 30_000)
    samples = Agent.get(snapshots, & &1)
    GenServer.stop(conn)

    report_appends(appends)
    IO.puts("")
    report_snapshots(samples)
  end

  defp append_run(subtransactions, progress) do
    {:ok, latencies} =
      SubxidRepo.transaction(fn ->
        Enum.map(1..subtransactions, fn n ->
          started = System.monotonic_time(:microsecond)

          {:ok, _events} =
            SubxidRepo.transaction(fn ->
              Trogon.Outbox.append(SubxidRepo, "bench-source", "event-#{n}", prefix: @prefix)
            end)

          Agent.update(progress, fn _ -> n end)
          {n, System.monotonic_time(:microsecond) - started}
        end)
      end)

    latencies
  end

  defp snapshot_loop(conn, progress, stop, snapshots) do
    if Agent.get(stop, & &1) do
      :ok
    else
      count = Agent.get(progress, & &1)
      started = System.monotonic_time(:microsecond)
      %Postgrex.Result{} = Postgrex.query!(conn, "SELECT pg_snapshot_xmin(pg_current_snapshot())", [])
      elapsed = System.monotonic_time(:microsecond) - started

      Agent.update(snapshots, &[{count, elapsed} | &1])
      Process.sleep(1)
      snapshot_loop(conn, progress, stop, snapshots)
    end
  end

  defp report_appends(appends) do
    IO.puts("| savepoints so far | append p50 us | append p99 us |")
    IO.puts("| --- | --- | --- |")

    appends
    |> Enum.chunk_every(@overflow_at)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, index} ->
      latencies = chunk |> Enum.map(&elem(&1, 1)) |> Enum.sort()
      from = index * @overflow_at + 1
      to = from + length(chunk) - 1
      IO.puts("| #{from}-#{to} | #{percentile(latencies, 0.50)} | #{percentile(latencies, 0.99)} |")
    end)
  end

  defp report_snapshots([]), do: IO.puts("no snapshot samples were collected")

  defp report_snapshots(samples) do
    {below, above} = Enum.split_with(samples, fn {count, _elapsed} -> count < @overflow_at end)

    IO.puts("| savepoints open | pg_current_snapshot p50 us | pg_current_snapshot p99 us |")
    IO.puts("| --- | --- | --- |")
    report_bucket("below #{@overflow_at}", below)
    report_bucket("#{@overflow_at} or more (overflowed)", above)
  end

  defp report_bucket(_label, []), do: :ok

  defp report_bucket(label, samples) do
    latencies = samples |> Enum.map(&elem(&1, 1)) |> Enum.sort()
    IO.puts("| #{label} | #{percentile(latencies, 0.50)} | #{percentile(latencies, 0.99)} |")
  end

  defp percentile([], _p), do: 0
  defp percentile(sorted, p), do: Enum.at(sorted, min(round(p * (length(sorted) - 1)), length(sorted) - 1))

  defp reinstall! do
    SQL.query!(SubxidRepo, "DROP SCHEMA IF EXISTS #{@prefix} CASCADE")
    SQL.query!(SubxidRepo, "CREATE SCHEMA #{@prefix}")
    Ecto.Migrator.run(SubxidRepo, [{1, SubxidMigration}], :up, all: true, prefix: @prefix, log: false)
  end
end

Trogon.Outbox.Bench.Subxid.run()
