defmodule Trogon.Outbox.Migrations.V1 do
  @moduledoc false

  use Ecto.Migration

  alias Trogon.Outbox.{Postgres, Retention}

  @spec up(keyword()) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    partitions = Keyword.get(opts, :partitions, 64)
    days_ahead = Keyword.get(opts, :days_ahead, 7)

    unless is_integer(partitions) and partitions > 0 and partitions <= 32_767 do
      raise ArgumentError, "partitions must be an integer between 1 and 32767, got: #{inspect(partitions)}"
    end

    if prefix != "public", do: execute(~s(CREATE SCHEMA IF NOT EXISTS "#{Postgres.validate_prefix!(prefix)}"))

    execute("""
    CREATE FUNCTION #{Postgres.name(prefix, "outbox_partition_count")}() RETURNS integer
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$ SELECT #{partitions} $$
    """)

    execute("""
    CREATE FUNCTION #{Postgres.name(prefix, "outbox_partition")}(source text) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $$ SELECT (((hashtextextended(source, 0) % #{partitions}) + #{partitions}) % #{partitions})::integer $$
    """)

    execute("""
    CREATE TABLE #{Postgres.events(prefix)} (
      id bigserial NOT NULL,
      source text NOT NULL,
      seq bigint NOT NULL,
      partition integer NOT NULL GENERATED ALWAYS AS (#{Postgres.name(prefix, "outbox_partition")}(source)) STORED,
      xid xid8 NOT NULL,
      payload bytea NOT NULL,
      inserted_at timestamptz NOT NULL DEFAULT now()
    ) PARTITION BY RANGE (inserted_at)
    """)

    execute("CREATE INDEX outbox_events_relay_index ON #{Postgres.events(prefix)} (partition, xid, id)")
    execute("CREATE INDEX outbox_events_source_index ON #{Postgres.events(prefix)} (source, seq)")

    execute("""
    CREATE TABLE #{Postgres.sources(prefix)} (
      source text PRIMARY KEY,
      seq bigint NOT NULL,
      xid xid8 NOT NULL
    ) WITH (fillfactor = 70, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000)
    """)

    execute("""
    CREATE TABLE #{Postgres.cursors(prefix)} (
      relay text NOT NULL,
      partition integer NOT NULL,
      xid xid8 NOT NULL DEFAULT '0',
      id bigint NOT NULL DEFAULT 0,
      advanced_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (relay, partition)
    ) WITH (fillfactor = 50, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 100)
    """)

    today = Date.utc_today()

    today
    |> Date.add(-1)
    |> Date.range(Date.add(today, days_ahead))
    |> Enum.each(&execute(Retention.create_partition_sql(prefix, &1)))

    :ok
  end

  @spec down(keyword()) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :prefix, "public")

    execute("DROP TABLE IF EXISTS #{Postgres.cursors(prefix)}")
    execute("DROP TABLE IF EXISTS #{Postgres.sources(prefix)}")
    execute("DROP TABLE IF EXISTS #{Postgres.events(prefix)}")
    execute("DROP FUNCTION IF EXISTS #{Postgres.name(prefix, "outbox_partition")}(text)")
    execute("DROP FUNCTION IF EXISTS #{Postgres.name(prefix, "outbox_partition_count")}()")
    :ok
  end
end
