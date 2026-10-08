# Measures what a backlog and large args cost an Oban relay, using Oban's own Basic engine.
#
#     TROGON_OUTBOX_BENCH_DATABASE_URL=ecto://postgres:postgres@localhost:5432/trogon_outbox_bench \
#       MIX_ENV=test mix run bench/oban_relay_bench.exs
#
# TROGON_OUTBOX_BENCH_BACKLOGS sets the available backlog sizes, "0,10000,100000,1000000" by default.
# Every fetch runs inside a transaction that is rolled back, so the backlog stays the same size
# for each sample. The connections disable Nagle's algorithm, because on some local Docker networks
# its interaction with delayed acknowledgements adds a fixed 200ms to multi-packet replies, which
# would swamp the numbers being measured.

defmodule Trogon.Outbox.ObanBench.Repo do
  use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
end

defmodule Trogon.Outbox.ObanBench.Migration do
  use Ecto.Migration

  def up, do: Oban.Migration.up(prefix: "oban_bench")
  def down, do: Oban.Migration.down(prefix: "oban_bench")
end

defmodule Trogon.Outbox.ObanBench.PublishWorker do
  use Oban.Worker, queue: :relay

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Trogon.Outbox.ObanBench do
  alias Ecto.Adapters.SQL
  alias Oban.Engines.Basic
  alias Trogon.Outbox.ObanBench.{Migration, PublishWorker, Repo}

  @prefix "oban_bench"
  @samples 100
  @large_samples 10
  @fetch_limit 10

  def run do
    url =
      System.get_env("TROGON_OUTBOX_BENCH_DATABASE_URL", "ecto://postgres:postgres@localhost:5432/trogon_outbox_bench")

    backlogs =
      "TROGON_OUTBOX_BENCH_BACKLOGS"
      |> System.get_env("0,10000,100000,1000000")
      |> String.split(",")
      |> Enum.map(&String.to_integer/1)

    Application.put_env(:trogon_outbox, Repo,
      url: url,
      pool_size: 4,
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
    reinstall!()

    %Postgrex.Result{rows: [[version]]} = SQL.query!(Repo, "SHOW server_version")

    IO.puts(
      "Postgres #{version}, fetch limit #{@fetch_limit}, #{@samples} samples per backlog row, #{@large_samples} per args row\n"
    )

    conf = Oban.Config.new(repo: Repo, prefix: @prefix, testing: :disabled, name: :oban_bench)

    backlog_fetch(conf, backlogs)
    IO.puts("")
    large_args(conf)
  end

  defp backlog_fetch(conf, backlogs) do
    IO.puts("| available backlog | fetch p50 ms | fetch p90 ms | fetch max ms | stored rows |")
    IO.puts("| --- | --- | --- | --- | --- |")

    for backlog <- backlogs do
      truncate!()
      insert_backlog!(backlog, %{"event_id" => "evt"})
      sorted = sample(@samples, fn -> fetch_and_roll_back(conf) end)

      IO.puts(
        "| #{backlog} | #{fmt(percentile(sorted, 0.5))} | #{fmt(percentile(sorted, 0.9))} | #{fmt(List.last(sorted))} | #{count!()} |"
      )
    end
  end

  defp large_args(conf) do
    IO.puts("| args bytes | content | insert p50 ms | fetch of #{@fetch_limit} p50 ms | stored bytes per row |")
    IO.puts("| --- | --- | --- | --- | --- |")

    for bytes <- [1_000, 100_000, 1_000_000, 10_000_000], content <- [:repetitive, :random] do
      truncate!()
      payload = payload(content, bytes)

      inserts =
        sample(@large_samples, fn ->
          {:ok, %Oban.Job{}} = Basic.insert_job(conf, PublishWorker.new(%{"payload" => payload}), [])
        end)

      fetches = sample(@large_samples, fn -> fetch_and_roll_back(conf) end)

      %Postgrex.Result{rows: [[stored]]} =
        SQL.query!(Repo, "SELECT avg(pg_column_size(args))::bigint FROM #{@prefix}.oban_jobs")

      IO.puts(
        "| #{bytes} | #{content} | #{fmt(percentile(inserts, 0.5))} | #{fmt(percentile(fetches, 0.5))} | #{stored} |"
      )
    end
  end

  defp payload(:repetitive, bytes), do: :binary.copy("x", bytes)
  defp payload(:random, bytes), do: bytes |> div(4) |> Kernel.*(3) |> :crypto.strong_rand_bytes() |> Base.encode64()

  defp fetch_and_roll_back(conf) do
    meta = %{queue: "relay", limit: @fetch_limit, node: "bench", uuid: Ecto.UUID.generate()}

    Repo.transaction(fn ->
      {:ok, {_meta, jobs}} = Basic.fetch_jobs(conf, meta, %{})
      Repo.rollback(length(jobs))
    end)
  end

  defp insert_backlog!(0, _args), do: :ok

  defp insert_backlog!(count, args) do
    SQL.query!(
      Repo,
      """
      INSERT INTO #{@prefix}.oban_jobs (state, queue, worker, args)
      SELECT 'available', 'relay', $1, $2::jsonb FROM generate_series(1, $3)
      """,
      [inspect(PublishWorker), args, count]
    )

    SQL.query!(Repo, "VACUUM ANALYZE #{@prefix}.oban_jobs")
  end

  defp sample(count, fun) do
    fun.()

    for _sample <- 1..count do
      started = System.monotonic_time(:microsecond)
      fun.()
      System.monotonic_time(:microsecond) - started
    end
    |> Enum.sort()
  end

  defp count! do
    %Postgrex.Result{rows: [[count]]} = SQL.query!(Repo, "SELECT count(*) FROM #{@prefix}.oban_jobs")
    count
  end

  defp truncate!, do: SQL.query!(Repo, "TRUNCATE #{@prefix}.oban_jobs")

  defp reinstall! do
    Ecto.Migrator.run(Repo, [{1, Migration}], :down, all: true, log: false)
    Ecto.Migrator.run(Repo, [{1, Migration}], :up, all: true, log: false)
  end

  defp percentile(sorted, quantile) do
    index = min(length(sorted) - 1, trunc(quantile * length(sorted)))
    Enum.at(sorted, index)
  end

  defp fmt(microseconds), do: :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
end

Trogon.Outbox.ObanBench.run()
