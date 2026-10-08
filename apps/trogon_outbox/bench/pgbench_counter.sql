\set source_number :client_id % :spread
BEGIN;
WITH head AS (
  INSERT INTO outbox_bench.outbox_sources AS s (source, seq, xid)
  VALUES ('source-' || :source_number::int, 1, pg_current_xact_id())
  ON CONFLICT (source) DO UPDATE
    SET seq = s.seq + EXCLUDED.seq, xid = GREATEST(s.xid, EXCLUDED.xid)
  RETURNING s.source, s.seq - 1 AS seq, s.xid
)
INSERT INTO outbox_bench.outbox_events (source, seq, xid, payload)
SELECT head.source, head.seq + 1, head.xid, convert_to(repeat('x', 200), 'UTF8') FROM head;
COMMIT;
