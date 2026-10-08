defmodule Trogon.Outbox.Relay.Store do
  @moduledoc false

  alias Trogon.Outbox.{Cursor, Event, LockNamespace, Partition, Position, Postgres, Seq, Source}
  alias Trogon.Outbox.Relay.Lag

  @spec backend_pid!(pid()) :: pos_integer()
  def backend_pid!(conn) do
    %Postgrex.Result{rows: [[pid]]} = Postgres.query!(conn, "SELECT pg_backend_pid()", [])
    pid
  end

  @spec partition_count!(pid(), String.t()) :: pos_integer()
  def partition_count!(conn, prefix) do
    %Postgrex.Result{rows: [[count]]} =
      Postgres.query!(conn, "SELECT #{Postgres.name(prefix, "outbox_partition_count")}()", [])

    count
  end

  @doc """
  The small integer id assigned to `relay` in the relay registry, creating the row on first use.

  Combined with a partition into a lock objid with `lock_objid/2`, it keeps two relay names from
  ever taking the same advisory lock, which a 32-bit hash of the name and partition could not
  promise.
  """
  @spec relay_id!(pid(), String.t(), String.t()) :: pos_integer()
  def relay_id!(conn, prefix, relay) do
    %Postgrex.Result{rows: [[id]]} =
      Postgres.query!(
        conn,
        """
        INSERT INTO #{Postgres.relays(prefix)} (relay) VALUES ($1)
        ON CONFLICT (relay) DO UPDATE SET relay = EXCLUDED.relay
        RETURNING id
        """,
        [relay]
      )

    id
  end

  @spec try_lock!(pid(), pos_integer(), [Partition.t()]) :: {pos_integer(), [Partition.t()]}
  def try_lock!(conn, relay_id, partitions) do
    %Postgrex.Result{rows: [[backend_pid, locked]]} =
      Postgres.query!(
        conn,
        """
        SELECT pg_backend_pid(), coalesce(array_agg(p ORDER BY p), '{}')
          FROM unnest($1::int[]) AS p
         WHERE pg_try_advisory_lock($2::int, (($3::int << 16) | p))
        """,
        [Enum.map(partitions, & &1.value), LockNamespace.relay(), relay_id]
      )

    {backend_pid, Enum.map(locked, &Partition.new!/1)}
  end

  @doc "The advisory lock objid for `relay_id` and `partition`, exposed for `pg_locks` assertions."
  @spec lock_objid(pos_integer(), Partition.t() | non_neg_integer()) :: integer()
  def lock_objid(relay_id, %Partition{value: value}), do: lock_objid(relay_id, value)
  def lock_objid(relay_id, partition) when is_integer(partition), do: relay_id * 0x10000 + partition

  @spec load_cursors!(pid(), String.t(), String.t(), [Partition.t()]) :: %{Partition.t() => Cursor.t()}
  def load_cursors!(conn, prefix, relay, partitions) do
    values = Enum.map(partitions, & &1.value)

    Postgres.query!(
      conn,
      "INSERT INTO #{Postgres.cursors(prefix)} (relay, partition) SELECT $1, unnest($2::int[]) ON CONFLICT DO NOTHING",
      [relay, values]
    )

    %Postgrex.Result{rows: rows} =
      Postgres.query!(
        conn,
        "SELECT partition, xid::text, id FROM #{Postgres.cursors(prefix)} WHERE relay = $1 AND partition = ANY($2::int[])",
        [relay, values]
      )

    Map.new(rows, fn [partition, xid, id] -> {Partition.new!(partition), Cursor.new(Postgres.xid(xid), id)} end)
  end

  @spec read!(pid(), String.t(), %{Partition.t() => Cursor.t()}, pos_integer(), pos_integer()) ::
          [{Partition.t(), [Event.t(), ...]}]
  def read!(conn, prefix, cursors, batch_size, backend_pid) do
    {partitions, xids, ids} =
      Enum.reduce(cursors, {[], [], []}, fn {partition, cursor}, {partitions, xids, ids} ->
        {[partition.value | partitions], [Integer.to_string(cursor.xid) | xids], [cursor.id | ids]}
      end)

    %Postgrex.Result{rows: rows} =
      Postgres.query!(
        conn,
        """
        SELECT c.partition, e.id, e.source, e.seq, e.xid::text, e.payload, e.inserted_at
          FROM unnest($1::int[], $2::text[], $3::bigint[]) AS c(partition, xid, id)
         CROSS JOIN LATERAL (
           SELECT id, source, seq, xid, payload, inserted_at
             FROM #{Postgres.events(prefix)} e
            WHERE e.partition = c.partition
              AND e.xid < pg_snapshot_xmin(pg_current_snapshot())
              AND (e.xid, e.id) > (c.xid::xid8, c.id)
            ORDER BY e.xid, e.id
            LIMIT $4
         ) e
         WHERE pg_backend_pid() = $5
         ORDER BY c.partition, e.xid, e.id
        """,
        [partitions, xids, ids, batch_size, backend_pid]
      )

    rows
    |> Enum.chunk_by(fn [partition | _rest] -> partition end)
    |> Enum.map(fn [[partition | _rest] | _more] = chunk ->
      partition = Partition.new!(partition)
      {partition, Enum.map(chunk, &to_event(&1, partition))}
    end)
  end

  @spec advance!(pid(), String.t(), String.t(), %{Partition.t() => Cursor.t()}, pos_integer()) ::
          :ok | {:error, :lock_lost}
  def advance!(_conn, _prefix, _relay, advances, _backend_pid) when map_size(advances) == 0, do: :ok

  def advance!(conn, prefix, relay, advances, backend_pid) do
    {partitions, xids, ids} =
      Enum.reduce(advances, {[], [], []}, fn {partition, cursor}, {partitions, xids, ids} ->
        {[partition.value | partitions], [Integer.to_string(cursor.xid) | xids], [cursor.id | ids]}
      end)

    %Postgrex.Result{num_rows: num_rows} =
      Postgres.query!(
        conn,
        """
        UPDATE #{Postgres.cursors(prefix)} AS c
           SET xid = n.xid::xid8, id = n.id, advanced_at = now()
          FROM unnest($2::int[], $3::text[], $4::bigint[]) AS n(partition, xid, id)
         WHERE c.relay = $1 AND c.partition = n.partition AND pg_backend_pid() = $5
        """,
        [relay, partitions, xids, ids, backend_pid]
      )

    if num_rows == map_size(advances), do: :ok, else: {:error, :lock_lost}
  end

  @doc """
  How far each of `cursors` trails the snapshot watermark: how many events below it remain
  unpublished, and the age of the oldest of them. Informational only, unlike `read!/5` and
  `advance!/5`, so it does not check `pg_backend_pid()` against a captured value; a relay whose
  connection has moved to a different backend finds out through those instead.
  """
  @spec lag!(pid(), String.t(), %{Partition.t() => Cursor.t()}) :: %{Partition.t() => Lag.t()}
  def lag!(_conn, _prefix, cursors) when map_size(cursors) == 0, do: %{}

  def lag!(conn, prefix, cursors) do
    {partitions, xids, ids} =
      Enum.reduce(cursors, {[], [], []}, fn {partition, cursor}, {partitions, xids, ids} ->
        {[partition.value | partitions], [Integer.to_string(cursor.xid) | xids], [cursor.id | ids]}
      end)

    %Postgrex.Result{rows: rows} =
      Postgres.query!(
        conn,
        """
        SELECT c.partition, count(e.id), coalesce(extract(epoch FROM now() - min(e.inserted_at)) * 1000, 0)::bigint
          FROM unnest($1::int[], $2::text[], $3::bigint[]) AS c(partition, xid, id)
          LEFT JOIN LATERAL (
            SELECT id, inserted_at
              FROM #{Postgres.events(prefix)} e
             WHERE e.partition = c.partition
               AND e.xid < pg_snapshot_xmin(pg_current_snapshot())
               AND (e.xid, e.id) > (c.xid::xid8, c.id)
          ) e ON true
         GROUP BY c.partition
        """,
        [partitions, xids, ids]
      )

    Map.new(rows, fn [partition, count, oldest_age_ms] ->
      {Partition.new!(partition), %Lag{count: count, oldest_event_age_ms: oldest_age_ms}}
    end)
  end

  @doc """
  How long, in milliseconds, the oldest other backend holding back the snapshot xmin has had its
  current transaction open, the reason `pg_snapshot_xmin(pg_current_snapshot())` trails the
  current time. `0` when nothing else is holding it back. `pg_stat_activity.backend_xmin` is set
  once a backend's current transaction has taken a snapshot, the same condition that keeps its
  xmin counted against every other snapshot; this is not scoped to the current database, since
  a transaction on an unrelated database on the same Postgres instance holds the xmin back too,
  the same way it holds back vacuum.
  """
  @spec watermark_holdback_ms!(pid()) :: non_neg_integer()
  def watermark_holdback_ms!(conn) do
    %Postgrex.Result{rows: [[age_ms]]} =
      Postgres.query!(
        conn,
        """
        SELECT coalesce(extract(epoch FROM now() - min(xact_start)) * 1000, 0)::bigint
          FROM pg_stat_activity
         WHERE pid <> pg_backend_pid() AND backend_xmin IS NOT NULL
        """,
        []
      )

    age_ms
  end

  defp to_event([_partition, id, source, seq, xid, payload, inserted_at], partition) do
    %Event{
      position: Position.new(Source.new!(source), Seq.new!(seq)),
      partition: partition,
      cursor: Cursor.new(Postgres.xid(xid), id),
      payload: payload,
      inserted_at: inserted_at
    }
  end
end
