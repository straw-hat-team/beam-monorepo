defmodule EventStoreDashboard.RepoCountTest do
  use ExUnit.Case, async: false

  alias EventStoreDashboard.Repo
  alias EventStoreDashboard.Test.Postgres

  @moduletag :postgres

  @restricted_role "eventstore_dashboard_restricted"

  setup_all do
    config = Postgres.config(database: "eventstore_dashboard_repo_count_test")
    Postgres.setup_database!(config)

    admin = Postgres.connect!(config)
    seed!(admin)

    Postgres.query!(admin, "DROP ROLE IF EXISTS #{@restricted_role}")
    Postgres.query!(admin, "CREATE ROLE #{@restricted_role} LOGIN PASSWORD 'restricted'")
    Postgres.query!(admin, "GRANT SELECT ON streams, subscriptions, snapshots TO #{@restricted_role}")

    restricted = Postgres.connect!(Keyword.merge(config, username: @restricted_role, password: "restricted"))

    %{admin: admin, ctx: Postgres.context(admin), restricted_ctx: Postgres.context(restricted)}
  end

  # EventStore's schema init also creates the `$all` stream, so streams total 43.
  defp seed!(conn) do
    Postgres.query!(conn, """
    INSERT INTO streams (stream_uuid, stream_version)
    SELECT 'account-' || n, 0 FROM generate_series(1, 30) AS n
    UNION ALL
    SELECT 'order-' || n, 0 FROM generate_series(1, 12) AS n
    """)

    Postgres.query!(conn, """
    INSERT INTO subscriptions (stream_uuid, subscription_name, last_seen)
    SELECT '$all', 'projector-' || n, 0 FROM generate_series(1, 7) AS n
    UNION ALL
    SELECT 'account-1', 'notifier', 0
    """)

    Postgres.query!(conn, """
    INSERT INTO snapshots (source_uuid, source_version, source_type, data, metadata)
    SELECT 'account-' || n, 1, 'Account', ''::bytea, ''::bytea FROM generate_series(1, 5) AS n
    UNION ALL
    SELECT 'order-1', 1, 'Order', ''::bytea, ''::bytea
    """)

    Postgres.query!(conn, "ANALYZE streams, subscriptions, snapshots")
  end

  # The unfiltered counts must come from pg_class, not COUNT(*). Rows added
  # after ANALYZE leave reltuples stale, which only the estimate path reports.
  describe "unfiltered counts" do
    setup %{admin: admin} do
      Postgres.query!(admin, "INSERT INTO subscriptions (stream_uuid, subscription_name) VALUES ('$all', 'late')")
      on_exit(fn -> Postgres.query!(admin, "DELETE FROM subscriptions WHERE subscription_name = 'late'") end)
      :ok
    end

    test "use the planner estimate instead of COUNT(*)", %{admin: admin, ctx: ctx} do
      assert Postgres.query!(admin, "SELECT COUNT(*) FROM subscriptions").rows == [[9]]
      assert Repo.count_subscriptions(node(), ctx, nil) == {:ok, 8}
      assert Repo.count_streams(node(), ctx, "%") == {:ok, 43}
      assert Repo.count_snapshots(node(), ctx, nil) == {:ok, 6}
    end
  end

  describe "estimate_count/3" do
    test "reads reltuples for each table", %{ctx: ctx} do
      assert Repo.estimate_count(node(), ctx, "streams") == {:ok, 43}
      assert Repo.estimate_count(node(), ctx, "subscriptions") == {:ok, 8}
      assert Repo.estimate_count(node(), ctx, "snapshots") == {:ok, 6}
    end

    test "clamps a never-analyzed table to zero", %{admin: admin, ctx: ctx} do
      Postgres.query!(admin, "CREATE TABLE never_analyzed (id int)")
      on_exit(fn -> Postgres.query!(admin, "DROP TABLE IF EXISTS never_analyzed") end)

      assert Repo.estimate_count(node(), ctx, "never_analyzed") == {:ok, 0}
    end

    test "returns :error for a missing table", %{ctx: ctx} do
      assert Repo.estimate_count(node(), ctx, "no_such_table") == :error
    end
  end

  describe "filtered counts" do
    test "streams count prefix matches exactly", %{ctx: ctx} do
      assert Repo.count_streams(node(), ctx, "order-%") == {:ok, 12}
    end

    test "subscriptions count ILIKE matches exactly", %{ctx: ctx} do
      assert Repo.count_subscriptions(node(), ctx, "%NOTIFIER%") == {:ok, 1}
      assert Repo.count_subscriptions(node(), ctx, "%account-1%") == {:ok, 1}
    end

    test "snapshots count matches exactly", %{ctx: ctx} do
      assert Repo.count_snapshots(node(), ctx, "%order%") == {:ok, 1}
    end
  end

  describe "when the role cannot read pg_class" do
    setup %{admin: admin} do
      Postgres.query!(admin, "REVOKE SELECT ON pg_catalog.pg_class FROM PUBLIC")
      on_exit(fn -> Postgres.query!(admin, "GRANT SELECT ON pg_catalog.pg_class TO PUBLIC") end)
      :ok
    end

    test "estimate_count/3 reports :restricted", %{restricted_ctx: ctx} do
      assert Repo.estimate_count(node(), ctx, "streams") == :restricted
    end

    test "unfiltered counts fall back to an exact COUNT(*)", %{restricted_ctx: ctx} do
      assert Repo.count_streams(node(), ctx, "%") == {:ok, 43}
      assert Repo.count_subscriptions(node(), ctx, nil) == {:ok, 8}
      assert Repo.count_snapshots(node(), ctx, nil) == {:ok, 6}
    end
  end
end
