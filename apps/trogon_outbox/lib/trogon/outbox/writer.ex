defmodule Trogon.Outbox.Writer do
  @moduledoc false

  alias Trogon.Outbox.{Cursor, Event, LockNamespace, Partition, Position, Postgres, Seq, Source}

  @spec append(module(), Source.t(), [binary(), ...], String.t(), Trogon.Outbox.strategy()) :: [Event.t()]
  def append(repo, %Source{} = source, payloads, prefix, :counter) do
    repo
    |> Postgres.query!(counter_sql(prefix), [source.value, length(payloads), payloads])
    |> to_events(source, payloads)
  end

  def append(repo, %Source{} = source, payloads, prefix, :advisory_lock) do
    %Postgrex.Result{rows: [[_lock, isolation]]} =
      Postgres.query!(
        repo,
        "SELECT pg_advisory_xact_lock($1::int, hashtext($2))::text, current_setting('transaction_isolation')",
        [LockNamespace.writer(), source.value]
      )

    if isolation != "read committed" do
      raise ArgumentError,
            "the :advisory_lock strategy reads the previous seq after taking the lock, which needs " <>
              "read committed isolation, got: #{isolation}"
    end

    repo
    |> Postgres.query!(advisory_lock_sql(prefix), [source.value, payloads])
    |> to_events(source, payloads)
  end

  defp counter_sql(prefix) do
    """
    WITH head AS (
      INSERT INTO #{Postgres.sources(prefix)} AS s (source, seq, xid)
      VALUES ($1, $2, pg_current_xact_id())
      ON CONFLICT (source) DO UPDATE
        SET seq = s.seq + EXCLUDED.seq, xid = GREATEST(s.xid, EXCLUDED.xid)
      RETURNING s.seq - $2 AS seq, s.xid
    )
    INSERT INTO #{Postgres.events(prefix)} (source, seq, xid, payload)
    SELECT $1, head.seq + p.ord, head.xid, p.payload
      FROM head, unnest($3::bytea[]) WITH ORDINALITY AS p(payload, ord)
     ORDER BY p.ord
    RETURNING id, seq, xid::text, partition, inserted_at
    """
  end

  defp advisory_lock_sql(prefix) do
    """
    WITH last AS (
      SELECT seq, xid FROM #{Postgres.events(prefix)} WHERE source = $1 ORDER BY seq DESC LIMIT 1
    ), head AS (
      SELECT coalesce((SELECT seq FROM last), 0) AS seq,
             GREATEST(coalesce((SELECT xid FROM last), '0'::xid8), pg_current_xact_id()) AS xid
    )
    INSERT INTO #{Postgres.events(prefix)} (source, seq, xid, payload)
    SELECT $1, head.seq + p.ord, head.xid, p.payload
      FROM head, unnest($2::bytea[]) WITH ORDINALITY AS p(payload, ord)
     ORDER BY p.ord
    RETURNING id, seq, xid::text, partition, inserted_at
    """
  end

  defp to_events(%Postgrex.Result{rows: rows}, source, payloads) do
    rows
    |> Enum.sort_by(fn [_id, seq | _rest] -> seq end)
    |> Enum.zip_with(payloads, fn [id, seq, xid, partition, inserted_at], payload ->
      %Event{
        position: Position.new(source, Seq.new!(seq)),
        partition: Partition.new!(partition),
        cursor: Cursor.new(Postgres.xid(xid), id),
        payload: payload,
        inserted_at: inserted_at
      }
    end)
  end
end
