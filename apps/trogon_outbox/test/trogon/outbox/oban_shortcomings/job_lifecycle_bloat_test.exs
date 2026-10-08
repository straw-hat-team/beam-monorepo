defmodule Trogon.Outbox.ObanShortcomings.JobLifecycleBloatTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  @jobs 1_000
  @bloat_pool_size 60

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  defmodule BloatRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
  end

  # Sized for the relay queue's own concurrency, so 50 workers reporting finished jobs don't
  # starve TestRepo's shared 10-connection pool.
  setup do
    config = TestRepo.config() |> Keyword.drop([:pool_size]) |> Keyword.put(:pool_size, @bloat_pool_size)
    Application.put_env(:trogon_outbox, BloatRepo, config)
    on_exit(fn -> Application.delete_env(:trogon_outbox, BloatRepo) end)
    start_supervised!(BloatRepo)

    ObanJobs.truncate!()
    SQL.query!(BloatRepo, "ALTER TABLE oban_jobs SET (autovacuum_enabled = false)")
    on_exit(fn -> SQL.query!(TestRepo, "ALTER TABLE oban_jobs RESET (autovacuum_enabled)") end)
    SQL.query!(BloatRepo, "VACUUM oban_jobs")
    :ok
  end

  # This deliberately stops at n_tup_upd/n_tup_hot_upd, which already prove every job cost a
  # non-HOT update, and does not also assert on n_dead_tup: Postgres opportunistically prunes
  # dead tuples on any page a query touches, not only during VACUUM, so the relay queue's own
  # fetch polling races to reclaim them while jobs are still in flight. Under load that race is
  # genuinely unwinnable (reproduced n_dead_tup landing anywhere from 0 to 1000), not a matter of
  # waiting or flushing stats longer.
  test "every published job costs at least two updates and none of them is a heap-only tuple update" do
    {updates_before, hot_before} = table_stats!()

    publish_all!(:bloat_updates)

    {updates_after, hot_after} = table_stats_until!(updates_before + 2 * @jobs)

    assert updates_after - updates_before >= 2 * @jobs
    assert hot_after - hot_before == 0
  end

  test "fetching from a queue with nothing available reads more index pages after jobs complete, until a vacuum" do
    empty_queue_buffers = fetch_buffers!()

    publish_all!(:bloat_fetch)

    after_publish_buffers = fetch_buffers!()
    SQL.query!(BloatRepo, "VACUUM oban_jobs")
    after_vacuum_buffers = fetch_buffers!()

    assert after_publish_buffers > empty_queue_buffers
    assert after_vacuum_buffers < after_publish_buffers
  end

  # Counts completions via telemetry instead of polling `oban_jobs` with SQL: a SELECT against
  # the table opportunistically prunes the dead tuples this test measures, so waiting on one
  # would erase the evidence under heavier load (more polls) before it's ever counted.
  defp publish_all!(name) do
    counter = :counters.new(1, [])
    handler_id = {__MODULE__, name}

    :telemetry.attach(
      handler_id,
      [:oban, :job, :stop],
      fn _event, _measurements, %{conf: %{name: ^name}}, _config -> :counters.add(counter, 1, 1) end,
      nil
    )

    start_supervised!({Oban, ObanInstance.opts(name, repo: BloatRepo, queues: [relay: 50])})
    Oban.insert_all(name, for(sequence <- 1..@jobs, do: PublishWorker.new(%{"sequence" => sequence})))

    assert ObanJobs.eventually(fn -> :counters.get(counter, 1) == @jobs end, 60_000)
    :telemetry.detach(handler_id)
    :ok = stop_supervised(name)
  end

  defp fetch_buffers! do
    BloatRepo.checkout(fn -> Enum.min(for _run <- 1..3, do: explain_fetch_buffers!()) end)
  end

  defp explain_fetch_buffers! do
    %Postgrex.Result{rows: [[[plan]]]} =
      SQL.query!(BloatRepo, """
      EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
      SELECT id FROM oban_jobs
      WHERE state = 'available' AND queue = 'relay'
      ORDER BY priority, scheduled_at, id
      LIMIT 10
      FOR UPDATE SKIP LOCKED
      """)

    plan["Plan"]["Shared Hit Blocks"] + plan["Plan"]["Shared Read Blocks"]
  end

  defp table_stats! do
    force_flush_all!()

    %Postgrex.Result{rows: [[updates, hot_updates]]} =
      SQL.query!(BloatRepo, "SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'oban_jobs'")

    {updates, hot_updates}
  end

  defp force_flush_all! do
    1..@bloat_pool_size
    |> Task.async_stream(
      fn _ -> BloatRepo.checkout(fn -> SQL.query!(BloatRepo, "SELECT pg_stat_force_next_flush()") end) end,
      max_concurrency: @bloat_pool_size,
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp table_stats_until!(expected_updates, attempts \\ 100) do
    {updates, _hot_updates} = stats = table_stats!()

    cond do
      updates >= expected_updates ->
        stats

      attempts == 0 ->
        flunk("pg_stat_user_tables never reported #{expected_updates} updates on oban_jobs, saw #{updates}")

      true ->
        Process.sleep(50)
        table_stats_until!(expected_updates, attempts - 1)
    end
  end
end
