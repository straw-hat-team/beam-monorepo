\set source_number :client_id % :spread
BEGIN;
SELECT pg_advisory_xact_lock(1414494066, hashtext('source-' || :source_number::int));
WITH last AS (
  SELECT seq, xid FROM outbox_bench.outbox_events
   WHERE source = 'source-' || :source_number::int ORDER BY seq DESC LIMIT 1
), head AS (
  SELECT coalesce((SELECT seq FROM last), 0) AS seq,
         GREATEST(coalesce((SELECT xid FROM last), '0'::xid8), pg_current_xact_id()) AS xid
)
INSERT INTO outbox_bench.outbox_events (source, seq, xid, payload)
SELECT 'source-' || :source_number::int, head.seq + 1, head.xid, convert_to(repeat('x', 200), 'UTF8') FROM head;
COMMIT;
