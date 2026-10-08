\set source_number :client_id % :spread
BEGIN;
WITH head AS (
  MERGE INTO outbox_bench.outbox_sources AS s
  USING (VALUES ('source-' || :source_number::int, 1, pg_current_xact_id())) AS v(source, seq, xid)
  ON s.source = v.source
  WHEN MATCHED THEN UPDATE SET seq = s.seq + v.seq, xid = GREATEST(s.xid, v.xid)
  WHEN NOT MATCHED THEN INSERT (source, seq, xid) VALUES (v.source, v.seq, v.xid)
  RETURNING s.source, s.seq - 1 AS seq, s.xid
)
INSERT INTO outbox_bench.outbox_events (source, seq, xid, payload)
SELECT head.source, head.seq + 1, head.xid, convert_to(repeat('x', 200), 'UTF8') FROM head;
COMMIT;
