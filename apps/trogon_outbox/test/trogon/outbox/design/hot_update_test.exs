defmodule Trogon.Outbox.Design.HotUpdateTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  @table "design_hot_streams"
  @bumps 20

  setup do
    drop_table!()
    on_exit(&drop_table!/0)
    :ok
  end

  test "a version bump is a heap-only tuple update when version is not indexed" do
    create_streams!(fillfactor: 70)
    seed_sources!(1)

    {updates, hot_updates} = stats_delta(fn -> bump_versions!("source-0001", @bumps) end, @bumps)

    assert updates == @bumps
    assert hot_updates == @bumps
  end

  test "a version bump is never a heap-only tuple update when version is indexed" do
    create_streams!(fillfactor: 70)
    SQL.query!(TestRepo, "CREATE INDEX #{@table}_version_index ON #{@table} (version)")
    seed_sources!(1)

    {updates, hot_updates} = stats_delta(fn -> bump_versions!("source-0001", @bumps) end, @bumps)

    assert updates == @bumps
    assert hot_updates == 0
  end

  test "a version bump on a full page is not heap-only at fillfactor 100" do
    create_streams!(fillfactor: 100)
    seed_sources!(1_000)

    assert first_source_block!() == 0

    {updates, hot_updates} = stats_delta(fn -> bump_versions!("source-0001", 1) end, 1)

    assert updates == 1
    assert hot_updates == 0
  end

  test "a version bump on a page filled to fillfactor 70 is heap-only" do
    create_streams!(fillfactor: 70)
    seed_sources!(1_000)

    assert first_source_block!() == 0

    {updates, hot_updates} = stats_delta(fn -> bump_versions!("source-0001", 1) end, 1)

    assert updates == 1
    assert hot_updates == 1
  end

  defp drop_table! do
    SQL.query!(TestRepo, "DROP TABLE IF EXISTS #{@table}")
  end

  defp create_streams!(fillfactor: fillfactor) do
    SQL.query!(TestRepo, """
    CREATE TABLE #{@table} (
      source text PRIMARY KEY,
      version bigint NOT NULL DEFAULT 0
    ) WITH (fillfactor = #{fillfactor}, autovacuum_enabled = false)
    """)
  end

  defp seed_sources!(count) do
    SQL.query!(
      TestRepo,
      "INSERT INTO #{@table} (source) SELECT 'source-' || lpad(n::text, 4, '0') FROM generate_series(1, $1) AS n",
      [count]
    )
  end

  defp first_source_block! do
    %Postgrex.Result{rows: [[block]]} =
      SQL.query!(TestRepo, "SELECT (ctid::text::point)[0]::int FROM #{@table} WHERE source = 'source-0001'")

    block
  end

  defp bump_versions!(source, times) do
    TestRepo.checkout(fn ->
      Enum.each(1..times, fn _ ->
        SQL.query!(TestRepo, "UPDATE #{@table} SET version = version + 1 WHERE source = $1", [source])
      end)

      if server_version_num!() >= 150_000, do: SQL.query!(TestRepo, "SELECT pg_stat_force_next_flush()")
    end)
  end

  defp stats_delta(fun, expected_updates) do
    {updates_before, hot_before} = table_stats!()
    fun.()
    {updates_after, hot_after} = table_stats_until(updates_before + expected_updates)
    {updates_after - updates_before, hot_after - hot_before}
  end

  defp table_stats! do
    %Postgrex.Result{rows: [[updates, hot_updates]]} =
      SQL.query!(
        TestRepo,
        "SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = $1",
        [@table]
      )

    {updates, hot_updates}
  end

  defp table_stats_until(expected_updates, attempts \\ 100) do
    {updates, _hot_updates} = stats = table_stats!()

    cond do
      updates >= expected_updates ->
        stats

      attempts == 0 ->
        flunk("pg_stat_user_tables never reported #{expected_updates} updates on #{@table}, saw #{updates}")

      true ->
        Process.sleep(50)
        table_stats_until(expected_updates, attempts - 1)
    end
  end

  defp server_version_num! do
    %Postgrex.Result{rows: [[version]]} = SQL.query!(TestRepo, "SELECT current_setting('server_version_num')::int")
    version
  end
end
