# Designing a Postgres outbox for order without contention

This explains how a Postgres-backed transactional outbox can keep events in
commit order per source without serializing every writer, and which Postgres
features keep the table cheap to write, read, and retain. It is the design
direction that follows from [the ordering gaps](ordering-gaps.md) and from
[the shortcomings of using Oban as a relay](oban-as-an-outbox-relay.md).

Claims backed by a test in this package name the test next to them. Tests of
the design ideas on bare SQL live under `test/trogon/outbox/design/`, and tests
of the implemented outbox live under `test/trogon/outbox/postgres_outbox/`.
Everything else is design reasoning that still needs a proof before the package
relies on it.

## What is implemented

`Trogon.Outbox` implements the direction at the end of this page. The
[how-to](../how-to/use-the-outbox.md) shows how to install and run it. The
public modules:

- `Trogon.Outbox.Migration`, with `up(prefix:, partitions:)`, `down(prefix:)`,
  and `migrated_version/2`. The installed version is recorded as a comment on
  the events table, and each version is its own module.
- `Trogon.Outbox.append/4`, which writes inside the caller's transaction and
  raises outside one, plus `partition_count/2` and `partition_of/3`.
- `Trogon.Outbox.Relay`, a process that publishes to a
  `Trogon.Outbox.Publisher`.
- `Trogon.Outbox.Publishers.RabbitMQ`, a publisher for RabbitMQ, with
  `Trogon.Outbox.Publishers.RabbitMQ.Connection` holding the broker
  connection and reconnecting on loss.
- `Trogon.Outbox.Retention`, which creates and drops daily partitions.
- `Trogon.Outbox.LockNamespace`, which holds the advisory lock classids.
- The value objects: `Source`, `Seq`, `Position`, `MessageId`, `Partition`,
  `Cursor`, `Event`, `Batch`, and `PostgresVersion`.

`Trogon.Outbox.Migration.up/1` and `Trogon.Outbox.Relay` both check
`PostgresVersion` against the server they connect to and raise before doing
anything else when it reports a `server_version_num` below 170000. See
"Postgres 17" below for why 17 is the floor.

### Schema

```sql
CREATE TABLE outbox_events (
  id bigserial NOT NULL,
  source text NOT NULL,
  seq bigint NOT NULL,
  partition integer NOT NULL GENERATED ALWAYS AS (outbox_partition(source)) STORED,
  xid xid8 NOT NULL,
  payload bytea NOT NULL,
  inserted_at timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (inserted_at);

CREATE INDEX outbox_events_relay_index ON outbox_events (partition, xid, id);
CREATE INDEX outbox_events_source_index ON outbox_events (source, seq);

CREATE TABLE outbox_sources (
  source text PRIMARY KEY,
  seq bigint NOT NULL,
  xid xid8 NOT NULL
) WITH (fillfactor = 70, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 1000);

CREATE TABLE outbox_cursors (
  relay text NOT NULL,
  partition integer NOT NULL,
  xid xid8 NOT NULL DEFAULT '0',
  id bigint NOT NULL DEFAULT 0,
  advanced_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relay, partition)
) WITH (fillfactor = 50, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 100);

CREATE TABLE outbox_relays (
  relay text PRIMARY KEY,
  id smallint NOT NULL GENERATED ALWAYS AS IDENTITY,
  UNIQUE (id)
);
```

`outbox_partition(source)` is an immutable SQL function, `hashtextextended`
of the source modulo the partition count fixed at install time, and
`outbox_partition_count()` returns that count. Each day gets a child table
named `outbox_events_YYYYMMDD`.

It differs from the sketches further down this page in a few places:

- The counter table is `outbox_sources (source, seq, xid)`, not
  `outbox_streams (source, version)`, and it is created on first use with an
  upsert.
- `xid` has no default. The writer computes it, as explained in "Commit order
  within a source".
- There is no `UNIQUE (source, seq)`. A unique index on a partitioned table must
  include the partition key, so it could not span days. Under the counter
  strategy the counter row already makes `(source, seq)` unique, and the
  `(source, seq)` index is plain.

### Gapless seq: the counter is the default

Both strategies are implemented, selected with the `:strategy` option of
`append/4`.

- `:counter`, the default, is one statement: an upsert on `outbox_sources`
  that returns the previous seq, chained with the insert into
  `outbox_events`.
- `:advisory_lock` takes `pg_advisory_xact_lock(writer_classid,
  hashtext(source))`, then reads the source's last row through the `(source,
  seq)` index and inserts after it. That costs a second round trip, and
  nothing is updated.

Each one gives a gapless seq per source, in commit order. Proof:
`append_test.exs`, "counter: concurrent writers with random rollbacks commit a
gapless seq per source" and "advisory_lock: concurrent writers with random
rollbacks commit a gapless seq per source".

The counter is the default for these reasons:

- **It is faster.** With the flush to disk taken out of the measurement, a
  single writer commits about 2.3 times as many appends with the counter, and
  concurrent writers on distinct sources about 2.4 to 2.6 times as many. On a
  single hot source the two are about equal, because the per-source lock
  bounds both. See "Benchmarks".
- **It survives retention.** The advisory lock strategy reads the previous seq
  from the events table, so once retention drops every event of a source its
  seq starts again at 1. The counter row keeps counting. Proof:
  `storage_test.exs`, "the advisory lock strategy restarts seq once retention
  drops a source's events, the counter does not".
- **It works at any isolation level.** Under repeatable read the advisory lock
  strategy would read the previous seq from a snapshot taken before the lock
  was granted, so it refuses to run outside read committed. Proof:
  `append_test.exs`, "the advisory lock strategy refuses repeatable read,
  where it would read a stale seq".
- **Its dead tuples are pruned on the page.** Counter bumps are heap-only
  tuple updates. A snapshot open in the same database, such as an
  autoanalyze, briefly stops page pruning, and an update that finds the page
  full during that pause moves the row to another page, so the test requires
  at least 95 percent rather than all of them. Proof: `storage_test.exs`,
  "counter bumps are heap-only tuple updates, short of brief pauses in page
  pruning".

### Commit order within a source

The snapshot watermark reads in `(xid, id)` order, and `seq` is assigned in
commit order under the per-source lock. Those two orders can disagree. A
transaction is assigned its xid on its first write, so a transaction that
writes a business row first holds an early xid, then waits on the source's
lock behind a transaction with a later xid. It commits after that transaction
and takes the higher seq, but sorts first by xid. With a third, unrelated
transaction open, the watermark can sit between the two xids. A relay would
then publish the higher seq first, and the lower seq after it once the
watermark passes.

The writer closes this by storing an ordering xid instead of its own. Under
the source's lock it stores the greater of its own xid and the ordering xid of
the source's previous event. The counter keeps the last ordering xid on the
counter row, and the advisory lock strategy reads it from the previous event.

- Within a source, ordering xids never decrease in seq order, and ids are taken
  under the same lock, so `(xid, id)` order equals seq order.
- The watermark stays safe. An event's ordering xid is at least the writer's
  own xid, so once it is below the watermark the writer has finished.
- Delivery waits no longer than it has to, because the previous event of the
  source committed before the lock was released.

Proof: `ordering_test.exs`, "counter: a transaction that writes before
appending takes an xid below the seq it commits after, and the ordering xid
hides the later seq until the earlier one is readable", the same test for
`advisory_lock`, and "counter: per-source commit order holds end to end with
concurrent writers, random rollbacks, and business writes before appending",
the same test for `advisory_lock`. When the writer stores its own xid instead,
both tests fail.

### Layout and retention

The events table is partitioned by `RANGE (inserted_at)`, one child per day,
with no default partition. The relay partition is a column, not a table
partition.

- **Why by time.** Retention then drops a whole table, which removes its file
  and leaves nothing for vacuum. Partitioning by relay partition would make
  retention a `DELETE`.
- **Why the relay partition is still cheap to read.** The relay index leads
  with `partition`, so a relay reads its partitions with an index range in
  every daily child. Each read visits every attached day, which is one more
  reason to keep retention current.
- **Why no default partition.** Rows in a default partition would block
  creating the matching day later. An insert for a day without a partition
  fails loudly instead, so `Retention.create_partitions/2` creates days ahead.

`Retention.drop_partitions/2` drops a day only when:

- every cursor of every relay for each partition has passed all of that day's
  rows. A partition without any cursor keeps the day, so a relay must have
  started before its events age out.
- the lock on the events table is granted within `:lock_timeout`, 100
  milliseconds by default. Otherwise the day is kept and retried on the next
  run, and writers never queue behind a long wait for the drop.

Dropping a day detaches it with `DETACH PARTITION ... CONCURRENTLY` before
dropping the now-standalone table, rather than dropping the partition in
place. A plain drop needs an exclusive lock on the whole events table, which
queues every append behind it; the concurrent detach needs a lock that does
not conflict with an append, and only waits, without blocking anything, for
a transaction already writing to that specific day to finish. An append to
the day being dropped itself either lands before the detach takes effect or
fails immediately once the day is gone, never queued. If that wait for an
already-granted lock outlasts `:lock_timeout`, the day is left detached but
not yet dropped; the next run finds it in that state and finishes it with
`DETACH PARTITION ... FINALIZE`, then attaches it back or drops it by the
same unpublished check that follows any detach. A day in that state skips the
unpublished check that normally decides whether to start: Postgres already
hides a partition pending detach from queries on the events table, so a relay
cannot read a late event committed into it, and waiting for that event to
publish first would keep the day pending, and its appends failing, forever.
If the detach actually
went through in the meantime and nothing is left pending, `FINALIZE` says so
instead of erroring, and that is treated as the detach having already
succeeded rather than as a failure.

The unpublished check above only decides whether to start a detach, not
whether it is safe to drop the table once it finishes: a transaction starting
after the check can still legally write to today's own day until it is
actually gone, since the detach only waits for writers already in progress,
it does not block a new one. This holds for every day the same way, not only
today, because `inserted_at` always defaults to `now()` at insert time and
nothing lets a caller backdate it, so a fresh transaction can never write to
a day that already ended either way. `drop_partitions/2` runs the unpublished
check again right after the detach succeeds, while the table is a
standalone, structurally frozen relation that nothing can insert into
anymore. If a writer landed in that window, the day is attached back instead
of dropped, and the next run tries again once every relay has actually
caught up to it. The detach's own lock wait, together with this second check,
is what keeps the guarantee uniformly; no separate check for transactions
open elsewhere in the database is needed on top of it.

Proof: `storage_test.exs`, "retention drops a published day whole, leaves no
dead tuples, and seq continues after it", "retention keeps a day that still
has unpublished events", "retention keeps a day while a transaction already
writing to it is still open", "retention does not wait on an open
transaction that has not written to the day being dropped", "retention keeps
a day until every relay with a cursor on it catches up, not only the first",
"retention keeps a day for an event a transaction committed late into it,
until the relay reads it", "retention never drops an event appended between
the unpublished check and the detach", "appends to the day being dropped
never stall, succeeding until the moment it is gone", and "relay batch reads
never stall while an older day is dropped with DETACH PARTITION CONCURRENTLY",
the last proving a concurrent relay's batch reads, not only appends, keep
flowing while a different day is detached and dropped.

Appending and publishing leave no dead tuples on the events table. Only
rolled-back appends do, and the test counts them. Proof: `storage_test.exs`,
"appending and publishing leaves no dead tuples on the events table, only
rolled-back appends do".

### Lock namespace

The outbox only takes two-integer advisory locks, `(classid, objid)`, with
fixed classids from `Trogon.Outbox.LockNamespace`:

- writers use `0x544F7772` with `hashtext(source)`.
- relays use `0x544F726C` with an objid built from the relay's row in
  `outbox_relays`, not a hash.

Postgres records a two-integer lock with `objsubid = 2` and a single-bigint
lock with `objsubid = 1`. Job libraries and application code usually take the
single-bigint form, so a bigint lock with the same bits as an outbox lock
never collides with it. Proof: `relay_lock_test.exs`, "the writer lock does
not collide with a single-bigint advisory lock of the same bits" and "the
writer lock does block a two-integer lock in the same namespace".

### Relay lock objids are assigned, not hashed

An earlier version built the relay lock's objid from `hashtext(prefix || ':'
|| relay || ':' || partition)`, a 32-bit hash of the whole key. Two relay
names can hash to the same 32-bit value for the same partition, and once they
do, the second relay can never hold a partition the first one already holds,
even though they are different relays with their own cursors. Proof:
`relay_lock_test.exs`, "two relay names whose hashtext collided under the old
scheme no longer share a lock", which finds a real colliding pair by hashing
candidate names in SQL.

`Trogon.Outbox.Relay.Store.relay_id!/3` assigns each relay name a `smallint`
id on first use, in `outbox_relays`. The lock objid is `(relay_id << 16) |
partition`. Partitions are capped at 32767 by the migration, and so is a
relay id, so the two halves never overlap and the combined value always fits
a signed 32-bit objid. Distinct `(relay_id, partition)` pairs always produce
distinct objids, which a hash cannot promise.

### The relay

A relay opens a dedicated Postgres connection, separate from the repo's pool,
and takes a session-level `pg_try_advisory_lock` per partition on it.

- **One relay per partition.** A second relay with the same name gets none of
  the held partitions. Proof: `relay_lock_test.exs`, "a second relay with the
  same name cannot take a partition that is held".
- **Takeover.** Unheld partitions are retried every `:lock_interval`, so any
  other relay with the same name is a standby. Every query checks that it
  still runs on the backend that took the locks. On a disconnect or a lost
  lock the relay stops instead of reconnecting without its locks. Proof:
  `relay_lock_test.exs`, "a standby takes over every partition once the
  holder's backend is terminated".
- **Reads** cover every held partition in one query, below the snapshot
  watermark and after each partition's `(xid, id)` cursor.
- **Cursors** advance per `(relay, partition)` only after the publisher
  returns `:ok`, as heap-only tuple updates with the same caveat as the
  counter. Proof: `storage_test.exs`, "cursor advances are heap-only tuple
  updates, short of brief pauses in page pruning".
- **Message ids** are `source:seq`, the same on every replay. Proof:
  `append_test.exs`, "the message id is stable from source and seq and parses
  back".
- **Polling** waits `:min_poll_interval` after a partial batch, polls again at
  once after a full one, and doubles up to `:max_poll_interval` while idle.
  `Relay.poll/1` wakes it early, so an application can send one coalesced
  wake-up from outside the business transaction instead of `NOTIFY` inside
  it. Proof: `relay_test.exs`, "polling wakes the relay without waiting for
  its backoff".
- **A silent network partition holds the lock until something terminates the
  backend.** A session-level advisory lock is released on disconnect, not on
  a timer of its own, so a relay whose connection goes quiet without closing
  keeps every partition it held and no standby takes over. Proof:
  `relay_network_partition_test.exs`, "a frozen connection keeps the session
  advisory lock, so a standby never takes over". Setting `idle_session_timeout`
  on the relay's connection bounds the stall, since Postgres terminates the
  backend once its own clock, not the network, says the session has been idle
  past the limit; a standby then acquires the lock within that bound. Proof:
  `relay_network_partition_test.exs`, "a short idle_session_timeout on the
  relay connection bounds standby takeover once the network freezes". See the
  how-to's "Run a relay" section for the setting.
- **A transaction-mode pooler can separate the lock from the relay that
  thinks it holds it.** The lock lives on whichever backend process serves
  the connection; a pooler such as PgBouncer in transaction mode can hand
  that connection's next statement to a different backend, so the relay
  keeps querying while the lock sits on a backend it no longer talks to.
  Every lock, read and advance already compares `pg_backend_pid()` against
  the one captured at startup and stops the relay on a mismatch, which
  catches this once it happens. `Trogon.Outbox.Relay.PoolerGuard`, opt-in via
  `:pooler_guard`, catches it earlier, at startup: a handful of auxiliary
  connections through the same configuration force contention while the
  relay's own connection is sampled for `pg_backend_pid()` several times, and
  more than one answer refuses the start with the reason. It is opt-in, not
  automatic, because the forcing itself opens connections and takes a moment,
  right as a relay is trying to start; append itself needs no such guard,
  since autocommit statements and single-statement transactions do not care
  which backend ran them. Proof: `transaction_pooler_test.exs`, "append
  commits through a transaction-mode pooler the same as a direct connection"
  and "a relay refuses to start when its own connection goes through a
  transaction-mode pooler". See the how-to's "Run a relay" section for the
  option.
- **Telemetry and on-demand health.** The relay emits `:telemetry` events for
  lock acquisition and loss as they happen, and for per-partition cursor lag
  and watermark holdback on a fixed `:telemetry_interval`, independent of its
  poll backoff. `Relay.health/1` returns the same read on demand instead of
  waiting for the next event: held and expected partitions, lag per held
  partition, and the current watermark holdback. Lag and holdback are
  read-only queries against the events, cursors, and `pg_stat_activity` the
  relay already touches, so reporting them adds no lock contention of its
  own. Proof: `relay_telemetry_test.exs`.

Delivery proofs, all in `relay_test.exs`:

- "a transaction that appended first but commits last is never skipped"
- "a rolled-back transaction is never delivered"
- "a long open transaction with an xid delays delivery but loses nothing"
- "a long open read-only transaction does not delay delivery"
- "a relay that crashes after publishing but before advancing replays the
  exact batch"
- "a publisher error leaves the cursor in place and the same batch is retried"
- "a partition whose publishes keep failing does not hold back the others"
- "relays with different names each publish every event"

Every test under `test/trogon/outbox/postgres_outbox/` passed in five
consecutive runs.

### Benchmarks

`bench/pgbench.sh` runs the append statement of each strategy through pgbench
on the database host, so the client network is not part of commit latency.
`bench/outbox_bench.exs` drives `Trogon.Outbox.append/4` and the relay from
Elixir. Neither is part of the test suite.

Measured on Postgres 17.11 in a container on an Apple M4 Max laptop with 14
cores and 36 GB of memory, through OrbStack, on a cluster other workloads were
using at the same time. Treat the numbers as a comparison between the
strategies, not as capacity figures. The cluster allowed 100 connections and
other workloads held about 40, so pgbench ran 32 writers at most instead of
64. Each run lasted 5 seconds, and the payload was 200 bytes.

With `synchronous_commit = off`, which takes the flush to disk out of the
measurement and leaves the cost of each strategy:

| strategy | writers | sources | commits/s | p50 ms | p99 ms |
| --- | --- | --- | --- | --- | --- |
| counter | 1 | same | 23020 | 0.04 | 0.11 |
| counter | 1 | distinct | 21972 | 0.04 | 0.13 |
| counter | 8 | same | 7543 | 0.72 | 4.89 |
| counter | 8 | distinct | 75342 | 0.06 | 0.71 |
| counter | 32 | same | 6724 | 3.15 | 23.06 |
| counter | 32 | distinct | 84427 | 0.13 | 5.61 |
| advisory_lock | 1 | same | 9777 | 0.09 | 0.27 |
| advisory_lock | 1 | distinct | 7890 | 0.09 | 0.30 |
| advisory_lock | 8 | same | 6819 | 1.09 | 3.05 |
| advisory_lock | 8 | distinct | 30983 | 0.15 | 1.23 |
| advisory_lock | 32 | same | 6250 | 4.79 | 9.57 |
| advisory_lock | 32 | distinct | 32891 | 0.38 | 7.34 |

With `synchronous_commit = on`, the flush dominates both strategies:

| strategy | writers | sources | commits/s | p50 ms | p99 ms |
| --- | --- | --- | --- | --- | --- |
| counter | 1 | same | 165 | 5.75 | 11.87 |
| counter | 1 | distinct | 150 | 5.87 | 17.41 |
| counter | 8 | same | 157 | 32.80 | 226.61 |
| counter | 8 | distinct | 659 | 11.56 | 23.11 |
| counter | 32 | same | 154 | 138.97 | 1041.80 |
| counter | 32 | distinct | 1426 | 23.59 | 35.00 |
| advisory_lock | 1 | same | 87 | 11.64 | 26.17 |
| advisory_lock | 1 | distinct | 153 | 5.97 | 13.00 |
| advisory_lock | 8 | same | 159 | 47.78 | 78.00 |
| advisory_lock | 8 | distinct | 667 | 11.55 | 21.76 |
| advisory_lock | 32 | same | 112 | 211.95 | 461.28 |
| advisory_lock | 32 | distinct | 1979 | 13.77 | 33.99 |

On a single hot source the counter's tail latency is higher than the advisory
lock's at 32 writers, probably because waiters on a row lock re-check the row
after the holder commits instead of being granted the lock in queue order,
though this is not proven here. Neither strategy scales on one source, and
that is the cost of a gapless per-source order.

From Elixir, through the client network, with 64 writers sharing 40
connections and `synchronous_commit = off`, the counter committed 709 appends
per second on one writer against 507 for the advisory lock, and 1661 against
842 with 64 writers on distinct sources. `outbox_bench.exs` now sets
`socket_options: [nodelay: true]` on its repo, the same way
`oban_relay_bench.exs` already does, to rule out the Nagle/delayed-ACK
interaction this section used to blame for the tail figures below, where the
network between the client and the container stalled for about 200
milliseconds on responses of more than a few kilobytes, even for a plain
`SELECT repeat('x', 20000)`. Running that same plain `SELECT repeat('x',
20000)` on its own, outside the full benchmark, shows no such stall today,
with or without `nodelay: true`: every round trip stays under a millisecond.
Whatever produced the fixed 200 millisecond stall is not present on this
machine right now, so `nodelay: true` neither confirms nor denies that
explanation, it only removes a variable that is not currently acting. Two
back to back full runs with `nodelay: true` still swing the end to end p99
below from 582 to 674 milliseconds and the max from 687 to 906 milliseconds,
seconds apart on an otherwise idle container, which is the same kind of
run-to-run noise on a shared laptop container that the Oban comparison below
already calls out, not a network stall.

| relay batch size | events | events/s |
| --- | --- | --- |
| 100 | 100000 | 90562 to 97166 |
| 500 | 100000 | 31611 to 100209 |
| 1000 | 100000 | 62058 to 68365 |

These are two runs with `nodelay: true`, each lasting a few seconds, back to
back on an otherwise idle container. Batch size 500 swings by more than 3x
between them, which says the swing is noise in this setup, not something
batch size or `nodelay: true` explains.

End to end, from before the business transaction starts to the publisher
call, with 8 writers on distinct sources and one relay, the same two runs
with `nodelay: true` gave a p50 of 140 to 184 milliseconds, a p99 of 582 to
674 milliseconds, and a max of 687 to 906 milliseconds, higher across the
board than the 120 to 200 millisecond p50 and 420 to 530 millisecond p99 this
section used to report without `nodelay: true`. The relay's own read takes
about 1.4 milliseconds inside Postgres for 64 partitions holding about 1400
events, so these figures still measure something outside the relay, in the
client or the network path, but `nodelay: true` did not shrink it, and per
the direct probe above, what it measures no longer looks like the Nagle
stall this doc used to name.

#### Against Oban OSS

`bench/outbox_vs_oban_bench.exs` runs `Trogon.Outbox.Relay` and a minimal
Oban OSS relay (a real queue, `testing: :disabled`, Oban's own Basic engine
and Database peer) back to back against the same
trogon-outbox-pg container, under their own schema and prefix so the two
runs never see each other's rows. It builds on the backlog-fetch and
large-args measurements above, which already live in
[Oban as an outbox relay](oban-as-an-outbox-relay.md#a-large-backlog-does-not-slow-the-fetch-but-large-args-do);
this run adds a sustained write-and-drain comparison and a table bloat
comparison, neither of which the fetch-only benchmark covers.

Both sides use 8 writers on distinct sources, matching the end-to-end
scenario above, each inserting as fast as it can (no pacing sleep) for 10
seconds, then draining whatever is left. Both connections disable Nagle's
algorithm for the reason given above. The outbox relay used its default
500-event batch size; the Oban queue ran with a local concurrency of 20.
Those are each project's own idea of a reasonable default, not a matched
pair, so read the comparison as "two systems as shipped," not as a
concurrency-controlled experiment. Postgres's `synchronous_commit` was left
at the container's default (`on`), so every commit waits on the WAL flush,
same as a production writer would. Measured on the same Apple M4 Max laptop
and Postgres 17.11 container as above, with other local workloads idle:

| relay | events | run seconds | events/s | p50 ms | p99 ms | max ms |
| --- | --- | --- | --- | --- | --- | --- |
| outbox relay | 2111 | 10.16 | 208 | 150.32 | 517.99 | 854.76 |
| Oban OSS relay | 1535 | 10.76 | 143 | 644.62 | 1227.53 | 1289.11 |

Both numbers moved between runs by a factor approaching 2 on the Oban side's
tail latency alone, on the same otherwise-idle machine, which says more
about how noisy a shared laptop container is than about either project; run
this more than once before trusting a single row of it.

Table bloat before the run, right after it (no vacuum), and after a plain
`VACUUM` of just that table:

| table | n_dead_tup before | n_dead_tup after | n_dead_tup after VACUUM | size before | size after | size after VACUUM |
| --- | --- | --- | --- | --- | --- | --- |
| race_outbox.outbox_events | 0 | 0 | 0 | 0.0 MiB | 0.0 MiB | 0.0 MiB |
| race_oban.oban_jobs | 0 | 2941 | 0 | 0.07 MiB | 1.5 MiB | 1.72 MiB |

`outbox_events` never acquires a dead tuple here because the relay only
reads it; nothing ever updates or deletes a row there, the cursor lives in
`outbox_cursors` instead (1 dead tuple, 0.06 MiB, after the same run).
`oban_jobs` picked up close to two dead tuples per job inserted, because
each one is updated in place from `available` to `executing` to
`completed`, two row versions behind before the row is eventually
prunable. A plain `VACUUM` took
`n_dead_tup` back to 0 on both tables, but did not shrink `oban_jobs` back
down: its size after vacuuming was larger than right after the run, since a
non-`FULL` vacuum frees space for reuse rather than returning it to the
filesystem, and visits the visibility map and free space map on the way.

This run stayed on the host, with only the socket-level fix above for the
Nagle stall; running the benchmark process itself inside a throwaway
container on trogon-outbox-pg's own bridge network, to remove the
client-to-container hop entirely, was not attempted. Doing that here would
mean building a container image with this project's exact Elixir and OTP
toolchain and compiling every dependency inside it, for one benchmark run,
which was judged not worth the time against what it would prove: the
numbers above are already dominated by `synchronous_commit = on` and by
each system's own concurrency model, not by the client network hop, which
the batch and large-args benchmarks already isolate and the nodelay fix
already addresses. Treat the throughput and latency numbers as one sample
on one machine, under one set of defaults, not as a verdict on either
project.

#### Batch confirms against per-message confirms

`bench/rabbitmq_confirm_bench.exs` publishes a fixed number of 200-byte
messages against a real RabbitMQ broker, confirming either once per batch
or once per message, at batch sizes from 1 to 1000. Measured against
trogon-outbox-rabbitmq on the same machine as above:

| confirms | batch size | messages/s | elapsed ms |
| --- | --- | --- | --- |
| batch | 1 | 124 | 40309.1 |
| batch | 100 | 4638 | 1078.1 |
| batch | 500 | 17798 | 280.9 |
| batch | 1000 | 31994 | 156.3 |
| per message | 1 | 96 | 52280.6 |

A batch size of 1 confirms once per message either way, and the two rows at
that size land within noise of each other, which is the expected floor for
both modes. Throughput rises with batch size because the broker round trip
for the confirm is paid once per batch rather than once per message; at a
batch size of 1000 the publisher moved about 258 times as many messages per
second as waiting for a confirm after every single message. This is the
behavior `Trogon.Outbox.Publishers.RabbitMQ` already has, publishing every
event in the batch before waiting for confirms once, so this benchmark is
evidence for keeping it, not a change it motivated.

Consumer-side order is a separate concern from this publisher's own
ordering guarantee; see "Order inside RabbitMQ" above for why it needs a
quorum queue with a single active consumer.

#### Savepoints and subtransaction overflow

A savepoint inside a business transaction becomes a subtransaction once it
performs a write, and Postgres caches up to 64 subtransaction XIDs per
backend in shared memory; the 65th marks that transaction `suboverflowed`,
after which any other session resolving the visibility of one of its rows
falls back to `pg_subtrans` instead of the cached array. `append/4` itself
does not open savepoints, but a caller nesting its own `Repo.transaction/2`
calls around it does, so a caller that nests widely enough to cross 64 is
worth measuring.

A caller's own nested `Repo.transaction/2` is not a savepoint: Ecto gives
nested calls no SQL `SAVEPOINT` of their own, so a `Repo.rollback/1` inside
one aborts the whole outer transaction and poisons the connection for
anything after it, rather than undoing only the inner scope. A caller that
wants to undo part of a transaction without losing the rest has to issue
`SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, and `RELEASE SAVEPOINT` itself.
`test/trogon/outbox/postgres_outbox/savepoint_test.exs` drives `append/4`
through exactly that, proving an append inside a savepoint that gets rolled
back leaves no seq gap, does not advance the per-source counter, and is
never read by the relay, while an append inside a savepoint that gets
released publishes with the next seq like any other append.

`bench/subxid_overflow_bench.exs` opens one business transaction, appends
inside 200 to 500 nested, committed savepoints, and times each append; a
second connection polls `pg_current_snapshot()`, the same call the relay's
watermark read makes, bucketed by how many savepoints the writer had opened
at the time. On this machine, through
OrbStack, append latency per savepoint and the snapshot call's p50 stayed
flat across the 64-savepoint boundary across repeated runs; the p99 of both
spiked to the same roughly 200 millisecond figure in both the below-64 and
overflowed buckets about equally often, matching the OrbStack network stall
already described above rather than tracking the overflow boundary. No
measurable overflow cost showed up here, and a figure dominated by that
stall would not be trustworthy evidence either way; this needs repeating on
a production-like network before concluding the cliff does not matter.

Until then, treat 64 nested savepoints in one business transaction as a
soft ceiling worth avoiding by design, not because of a measured cost but
because Postgres's own documentation names the fallback path as a source of
`pg_subtrans` contention under concurrent load, a condition this
single-writer benchmark cannot exercise. A caller that needs more than a
handful of savepoints around one append is very likely composing unrelated
units of work into one transaction, which is also a reason to split it on
its own terms.

### Postgres 17

Postgres 17 is the floor, enforced by `PostgresVersion` at migration and relay
start. Below are the version's features that were measured against this
design, adopted or rejected on the evidence.

**`transaction_timeout`, adopted as a required writer-role setting.** An open
transaction with an assigned xid holds back the snapshot watermark every
relay reads behind, stalling delivery for every source, not only the one the
transaction belongs to. Proof: `relay_test.exs`, "a long open transaction with
an xid delays delivery but loses nothing", five distinct sources held back by
one open transaction on a sixth. Setting `transaction_timeout` bounds the
stall by terminating the session once its current transaction has run longer
than the limit. Proof: `relay_test.exs`, "transaction_timeout armed before the
long transaction takes its xid bounds the delay".

The library does not set it. Postgres arms the timer from when the GUC takes
effect, not retroactively from the transaction's actual start, confirmed
against a live server: a transaction left open for longer than the limit and
only then given `SET transaction_timeout` keeps running past the limit,
instead of being terminated immediately. A `SET LOCAL` inside `append/4` would
only bound transactions that call `append/4` early enough in their lifetime,
missing both the transactions that never call it and the ones that open long
before they do. Setting it on the writer role instead covers every
transaction from the moment it starts, including ones that never touch the
outbox. See the how-to's "Append in a transaction" section for the setting.

**`idle_session_timeout`, adopted as a recommended relay connection
setting.** A relay's session advisory lock survives any failure that leaves
the TCP connection open without exchanging bytes, since Postgres only
releases the lock when the backend actually disconnects. A proxy that
withholds every byte in both directions without closing either socket
reproduces this: `tcp_keepalives_*` cannot catch it, because TCP keepalive
probes are themselves bytes the proxy withholds too, and the sockets on
both sides stay fully established throughout. `idle_session_timeout` does
catch it, because it is Postgres's own clock, independent of whether the
network is actually carrying traffic. Setting it on the relay's connection,
through `:connection parameters: [idle_session_timeout: ...]`, terminates
the stuck backend once the session has been idle past the limit, releasing
the lock for a standby to acquire. Proof: "The relay" above.

The library does not set it. An operator needs to size the limit above the
relay's own poll interval plus normal query latency, so a value that fits one
deployment's polling cadence may terminate another's idle-but-healthy relay
too eagerly; the relay only adds the connection's `:parameters` into the
startup packet it already sends, the same extension point `transaction_timeout`
uses below.

**`MERGE ... RETURNING`, evaluated and rejected for the counter strategy.** It
can replace the `INSERT ... ON CONFLICT DO UPDATE ... RETURNING` statement in
"The counter row" without changing the gapless seq guarantee, confirmed by
running it through the same modifying-CTE shape against the real schema. It
is not simpler: `ON CONFLICT` expresses the same match-or-insert decision in
one clause, where `MERGE` needs a `USING (VALUES ...)` source relation plus a
separate `WHEN MATCHED` and `WHEN NOT MATCHED` branch for it. It is not
consistently faster either. `bench/pgbench_merge.sql`, run through
`bench/pgbench.sh` the same way as the counter and advisory lock strategies,
on the database host with `synchronous_commit = off`:

| strategy | writers | sources | commits/s | p50 ms | p99 ms |
| --- | --- | --- | --- | --- | --- |
| counter | 1 | same | 22654 | 0.04 | 0.12 |
| counter | 1 | distinct | 21643 | 0.04 | 0.13 |
| counter | 8 | same | 10008 | 0.56 | 3.58 |
| counter | 8 | distinct | 69479 | 0.06 | 0.72 |
| counter | 32 | same | 6819 | 3.11 | 24.06 |
| counter | 32 | distinct | 78775 | 0.15 | 5.48 |
| merge | 1 | same | 21067 | 0.04 | 0.10 |
| merge | 1 | distinct | 21710 | 0.04 | 0.13 |
| merge | 8 | same | 10374 | 0.18 | 0.41 |
| merge | 8 | distinct | 73496 | 0.06 | 0.64 |
| merge | 32 | same | 9132 | 1.67 | 11.45 |
| merge | 32 | distinct | 83223 | 0.16 | 5.58 |

At 1 and 8 writers the two are within noise of each other. At 32 writers on
one hot source, where the counter's tail latency is already called out as
unexplained in "Benchmarks", `MERGE` looked better on this run but not on a
repeat: a second pair of runs at 32 writers on one source put the counter at
6190 to 7454 commits/s and `MERGE` at 7344 to 8335, overlapping ranges rather
than a consistent win. Without a repeatable advantage and without a
simplification, `MERGE` is not adopted; `bench/pgbench_merge.sql` stays in the
tree so the comparison can be rerun.

**Everything else evaluated.** `pg_stat_io`, added in Postgres 16 and so
already available at the 17 floor, is called out under "What to monitor" for
distinguishing cache hits from physical reads on the counter and cursor rows.
Postgres 17's smaller, faster vacuum map benefits the events, sources, and
cursors tables' autovacuum passes without any code change, since it is a
planner and executor change rather than new SQL surface. Nothing else in
Postgres 15 through 17 changed a write, read, or retention statement enough to
act on: no new relevant index type, no change to how `DETACH PARTITION
CONCURRENTLY` behaves, and no replacement for advisory locks or
`pg_try_advisory_lock`.

### Not proven yet

- The `NOTIFY` commit lock, as described in "The commit path".
- Any broker contract beyond RabbitMQ.
- Writes at 64 concurrent connections, end-to-end latency on a network without
  the stalls described in "Benchmarks", and freezing work on old event
  partitions.

## What order is worth paying for

A total order across every event in the system needs a single global lock or
sequence, and every writer then waits on every other writer. Consumers almost
never need that. They need events for one aggregate, stream, or tenant to
arrive in the order those transactions committed. The design therefore
promises commit order within a source and nothing across sources, which lets
unrelated writers proceed in parallel.

## Write side: serialize per source, not per table

Each source keeps a counter row, bumped inside the business transaction:

```sql
UPDATE outbox_streams
   SET version = version + 1
 WHERE source = $1
RETURNING version;

INSERT INTO outbox_events (source, seq, payload)
VALUES ($1, $2, $3);
```

with `UNIQUE (source, seq)` on `outbox_events`.

The `UPDATE` assumes the source already has a counter row. To create it on
first use in the same statement, use an upsert, which takes the same row lock
once the row exists:

```sql
INSERT INTO outbox_streams (source, version) VALUES ($1, 1)
ON CONFLICT (source) DO UPDATE SET version = outbox_streams.version + 1
RETURNING version;
```

The tests cover the `UPDATE` form, not the upsert.

- The row lock on the counter serializes only transactions that write the same
  source. Those transactions usually conflict on the aggregate anyway. Proof:
  `per_source_counter_test.exs`, "a writer on source B is not blocked by an
  open transaction on source A" and "a second writer on source A waits on the
  first writer's row lock and proceeds only after it commits".
- The sequence is gapless. A rolled-back transaction rolls back its counter
  bump, so `seq` is exactly the commit order within the source. Proof:
  `per_source_counter_test.exs`, "a rolled-back writer leaves no gap and seq
  follows commit order within a source" and "concurrent writers with random
  rollbacks on one source commit a contiguous seq from 1".
- In an event-sourced system the counter is the stream version already used
  for optimistic concurrency. An expected-version check turns waiting into a
  fast conflict.
- A transaction-scoped advisory lock on a hash of the source gives the same
  serialization without a counter row. The test "an advisory lock taken
  before insert serializes commits so id order matches commit order" in
  `id_order_vs_commit_order_test.exs` proves that id order then matches commit
  order. A stored `seq` is still worth having, so the relay detects gaps
  without trusting ids.

## Read side: never skip an in-flight transaction

Per-source order on write is not enough. A relay that reads `WHERE id >
last_id` can move past a row whose transaction took its id earlier but
committed later, and never see it. There are two ways to read in commit-safe
order.

### Snapshot watermark

Store the writing transaction id on each row with `xid xid8 DEFAULT
pg_current_xact_id()`, and only read rows older than every transaction still
in flight:

```sql
SELECT *
  FROM outbox_events
 WHERE xid < pg_snapshot_xmin(pg_current_snapshot())
   AND (xid, id) > ($cursor_xid, $cursor_id)
 ORDER BY xid, id
 LIMIT 500;
```

The cursor is the `(xid, id)` pair of the last row read, because one
transaction can write more rows than a batch holds.

Every transaction below the snapshot's xmin has either committed or aborted,
so no row can appear behind the watermark later. Proof:
`snapshot_watermark_test.exs`, "an id > last_id cursor skips a row whose
transaction took its id first but committed last" and "a snapshot watermark
cursor reads a row whose transaction took its id first but committed last".

The trade-off is that any long-running transaction that has been assigned a
transaction id holds the watermark back, in any database on the same Postgres
cluster, not only the outbox database. A read-only transaction that has not
written anything does not. Proof: the same file, "a long-open transaction with
an assigned xid holds pg_snapshot_xmin back even after later transactions
commit", "a long-open read-only transaction without an assigned xid does not
hold pg_snapshot_xmin back", and "an open transaction in another database of
the same cluster holds pg_snapshot_xmin back".

### Logical decoding

Logical replication streams changes in commit order from the write-ahead log.
Inserts take no extra locks and the relay does not poll. The cost is operating
a replication slot, covered in "Skipping the table" below.

#### Spike: pgoutput against the snapshot watermark

A spike (`bench/spikes/logical_decoding_spike.exs`) decodes `outbox_events`
inserts straight from `pgoutput` with `Postgrex.ReplicationConnection`, on a
throwaway `postgres:17` container running with `wal_level=logical`, and
compares the result against the snapshot watermark relay.

- **Ordering.** Two transactions take their xid in one order and commit in
  the other. pgoutput delivered them in commit order, not xid-assignment
  order, matching what the snapshot watermark already proves in
  `snapshot_watermark_test.exs`.
- **The open-transaction stall disappears.** A transaction held an xid open
  for roughly 2 seconds. Five inserts committed by other transactions while
  it was still open were decoded 40 to 76 ms after that transaction took its
  xid, not after it released it. The snapshot watermark would hold every one
  of those rows back until the long transaction committed or aborted
  (`relay_test.exs`, "a long open transaction with an xid delays delivery but
  loses nothing"). Logical decoding removes that stall by construction: it
  never computes a watermark, so nothing elsewhere in the cluster can hold it
  back.
- **Slot WAL retention is a real, measurable cost.** A slot with no consumer
  attached retained about 106 KB of WAL after 200 inserts it never read, up
  from 56 bytes idle, while a slot being actively drained did not grow. This
  is the mechanism behind "a stuck consumer fills the disk": unlike the
  snapshot watermark, where a stalled relay only delays delivery, a stalled
  logical decoding consumer makes Postgres hold WAL it would otherwise
  recycle.
- **Under-acking replays large amounts of already-delivered WAL.** The spike
  only sends a Standby Status Update when the server asks for one, never
  after actually processing a message. Stopping the consumer, inserting one
  row, then reconnecting to the same slot replayed 2208 already-delivered
  events before reaching the new one. A consumer that does not explicitly ack
  its own progress pays for that on every restart, proportional to how much
  WAL has accumulated since its last ack, not to how much work is actually
  pending.
- **Throughput is comparable at this scale.** 2000 inserts across 50
  transactions of 40 rows each: roughly 2300 to 3300 events/s to insert, and
  1980 to 2700 events/s to insert and fully decode. This ran against a
  dedicated container reached directly on `localhost`, not through the
  `*.orb.local` path the other benchmarks use, and at a much smaller row
  count, so the two throughput numbers are not directly comparable to the
  Oban or `outbox_bench.exs` results above.

Further costs a production consumer would carry:

- **Retention has no safe cap.** `max_slot_wal_keep_size` only turns unbounded
  WAL retention into a dropped slot, which loses the consumer's position.
- **Slot loss on failover.** A slot is not carried over by physical streaming
  replication unless the cluster adopts PG17 failover slots and the
  synchronous replication they require, so a promotion forces a resync.
- **Partition names leak through.** `outbox_events` is partitioned by day and
  `publish_via_partition_root` defaults to false, so Relation messages name
  the child partition (`outbox_events_20261007`), not the parent. The spike
  did not exercise a slot across a rotation that creates a new partition.
- **Hand-rolled decoding.** `Postgrex.ReplicationConnection` streams the wire
  protocol but does not parse it, and Relation messages carry column names,
  not types, so a production decoder needs its own type OID mapping.
- **Schema changes.** `pgoutput` streams row changes, not DDL, so a column
  change needs the consumer to pick up a new Relation message correctly.

**Recommendation.** Do not switch the relay to logical decoding now. The
snapshot watermark's stall has a cheaper mitigation already in place
(bounding transaction duration, see "Postgres 17" below), while logical
decoding trades that stall for a slot that must be monitored for retention,
rebuilt on failover, and acked by the consumer's own progress rather than by
the server's keepalive cadence. Keep logical decoding as the documented
escape hatch: if the open-transaction stall ever becomes a real operational
problem that bounding transaction duration cannot fix, this spike shows it is
viable and already proves the stall goes away.

## Publish side: partition by source, gate in memory

Hash each source to one of a fixed number of relay partitions, each with a
single consumer. Within a partition the consumer publishes in `(source, seq)`
order and advances a source only when `seq - 1` is published. The predecessor
gate becomes an in-memory check instead of a query per event, and parallelism
comes from the partition count rather than from competing workers. The
implementation needs no gate at all, because the ordering xid makes the
watermark read return each source in seq order. Every
message carries `(source, seq)` or a stable event id, so consumers can drop
the duplicates that at-least-once delivery still produces.

## Table layout

- **Append-only events.** Never `UPDATE outbox_events SET published_at`. Each
  relay partition stores its progress in a small cursor table keyed by
  partition. Updating every event row creates dead tuples, index churn, and
  vacuum debt on the hottest table.
- **Time partitioning.** Partition `outbox_events` by day or hour, for example
  with `pg_partman`. Retention is `DETACH PARTITION` and `DROP TABLE`, which
  frees space immediately and leaves nothing for vacuum, instead of `DELETE`.
- **No foreign keys** from the outbox to business tables. They add a lookup
  and a lock on every insert and complicate retention.
- **Payload compression.** `ALTER TABLE outbox_events ALTER COLUMN payload SET
  COMPRESSION lz4` makes out-of-line payloads cheaper to write and read than
  the default `pglz`.

## Indexes

- Keep only `UNIQUE (source, seq)` and the column the relay scans by (`xid` or
  `id`). Every additional index is paid on every insert.
- Use a BRIN index on `created_at` for time-range and retention queries. On
  append-only data it is tiny and almost free to maintain.
- If a status column exists anyway, index only the unpublished rows with a
  partial index `WHERE published_at IS NULL`.

## The counter row

The counter row is updated constantly by a small set of hot sources.

- Set `fillfactor` on `outbox_streams` to around 70 so the version bump stays
  a heap-only tuple update that touches no index. The fillfactor only matters
  once a page fills up: a full page at fillfactor 100 has no room for the new
  row version on the same page. Proof: `hot_update_test.exs`, "a version bump
  on a full page is not heap-only at fillfactor 100" and "a version bump on a
  page filled to fillfactor 70 is heap-only".
- Do not index `version`. An indexed column changing disables heap-only tuple
  updates. Proof: the same file, "a version bump is a heap-only tuple update
  when version is not indexed" and "a version bump is never a heap-only tuple
  update when version is indexed".
- Tune autovacuum per table, for example `autovacuum_vacuum_scale_factor = 0`
  with a small fixed `autovacuum_vacuum_threshold`, because a few rows churn
  continuously.

## The commit path

- **No `pg_notify` in the business transaction.** Postgres takes a single
  cluster-wide lock while committing a transaction that issued `NOTIFY`, held
  until the commit finishes, so every notifying transaction in every database
  on the cluster commits one at a time. Transactions that do not notify are
  not serialized by it. This was confirmed by load testing and lock sampling,
  not by a test: the lock is held too briefly to catch deterministically. Poll
  on a short interval, or send one coalesced notification per batch from
  outside the business transaction.
- **What `NOTIFY` does guarantee.** A listener never hears a notification
  before its transaction commits, hears notifications in commit order rather
  than the order `NOTIFY` was issued, and never hears one from a rolled-back
  transaction. That makes a notification a safe wake-up signal, not an
  ordering mechanism. Proof: `notify_ordering_test.exs`, "a listener receives
  no notification from a transaction that has not committed yet",
  "notifications are delivered in commit order, not in the order NOTIFY was
  issued", and "a notification from a rolled-back transaction is never
  delivered".
- **Batch inserts.** A business transaction that emits several events inserts
  them with one multi-row `INSERT`.
- **Short transactions.** An open transaction holds back both the snapshot
  watermark and vacuum.

## Relay reads

- Read in batches with an index range on the cursor and `LIMIT`, never
  `OFFSET`.
- With one consumer per partition no row locks are needed. If several workers
  share a partition, `FOR UPDATE SKIP LOCKED` keeps them from waiting on each
  other, at the cost of the in-memory gate.
- Advance the cursor once per batch. Cursor writes can use `SET LOCAL
  synchronous_commit = off`, because losing one only replays a batch that
  consumers already deduplicate.
- Reading from a replica requires computing the watermark on that replica, not
  on the primary.

## Skipping the table

`pg_logical_emit_message(true, 'outbox', payload)` writes the event straight
into the write-ahead log, transactionally, in commit order, with no table,
index, vacuum, or retention. A logical decoding consumer reads the messages
from a replication slot.

- Replay depends on retained WAL, not on rows. Set `max_slot_wal_keep_size`
  and alert on slot lag, because a stuck consumer otherwise fills the disk.
- A middle ground keeps a short-retention events table for replay and
  debugging while delivering through logical decoding.

## Avoiding dead tuples

Postgres leaves a dead tuple behind every `UPDATE` and `DELETE`, and behind
every insert whose transaction rolls back. They cannot be avoided entirely,
but the outbox can be shaped so almost none are created and the rest are
cleaned up without waiting for vacuum.

- **Events.** Append-only rows leave dead tuples only from rolled-back
  business transactions. Retention by `DROP PARTITION` or `TRUNCATE` removes
  whole files and leaves nothing for vacuum.
- **The counter row.** Every version bump leaves a dead tuple. A heap-only
  tuple update lets later reads and writes prune it on the page, with no index
  entries to clean. The alternative drops the counter row entirely: take
  `pg_advisory_xact_lock(hashtext(source))`, then compute `max(seq) + 1` from
  `outbox_events` through the `UNIQUE (source, seq)` index. A rollback removes
  the insert, so the sequence stays gapless, and nothing is ever updated. A
  Postgres `SEQUENCE` per source does not work, because sequences ignore
  rollbacks and leave gaps.
- **The relay cursor.** A single small row updated once per batch is cheap
  with the same tuning, or the cursor can live outside Postgres entirely.
- **No rows at all.** `pg_logical_emit_message`, described in "Skipping the
  table", writes no tuples.

Cleanup can still stall. A long-running transaction, or a replica
with `hot_standby_feedback` on, stops cleanup everywhere, including page-level
pruning of the counter row. And append-only tables still need freezing:
Postgres 13 and later starts autovacuum from insert counts, and dropping
partitions before they age out avoids most of that work.

"Layout and retention" proves the events table and retention parts of this
section, and the heap-only tuple tests prove the counter and cursor parts.
The effect of a long-running transaction or `hot_standby_feedback` on cleanup
is not proven here.

## Ticks and rotation

[PgQue](https://pgque.dev/) is a rebuild of
[PgQ](https://github.com/pgq/pgq) as plain SQL and PL/pgSQL that applies
these ideas as a queue. Its own description is "Snapshot-based batching and
TRUNCATE-based rotation instead of per-row DELETE. No dead tuples in the hot
path, immune to xmin-horizon pinning."

- **Ticks.** A ticker records a transaction snapshot on an interval, 100
  milliseconds by default. A batch is every event committed between two
  ticks. This is the snapshot watermark from "Read side" taken on a schedule,
  so a late-committing transaction is never skipped.
- **Insert-only events.** Consumers never update event rows. Each consumer
  keeps its own cursor on the shared log.
- **Rotation.** Event tables rotate, and a table is truncated once every
  consumer has passed it.
- **One notification per tick,** never one per business transaction, so the
  commit-time `NOTIFY` lock described in "The commit path" never applies to
  writers.
- **Sending is plain SQL** inside the business transaction, so the event is
  atomic with the business write. Sending, ticking, and receiving must run in
  separate transactions.

Stated requirements and costs: Postgres 14 or later, pg_cron 1.5 or later to
drive the ticker, and a median delivery latency of about 50 milliseconds at
the default tick. Retry with backoff and a dead letter queue are built in.
Cooperative consumers that split one batch across workers are marked
experimental.

The documentation does not state an ordering guarantee per key, what a long
open transaction does to batch delivery, or what happens when a consumer
falls behind a rotation. Those need a proof before the package relies on
PgQue.

## One relay per broker, partitioned for later

The relay publishes to RabbitMQ, Amazon SQS, or Kafka, and RabbitMQ is the
only target for now. The target deployment is a single relay that publishes
every event to the broker, with room to grow to one relay per partition later
without a redesign. Everything up to the broker call is the same for every
target. What changes per broker is how it acknowledges a publish and how it
keeps order.

### Partitions from the start

- **Fixed partitions at write time.** Each source maps to one of a fixed
  number of queues, `hash(source) mod N`. Choose N generously, such as 32 or
  64. An empty partition costs almost nothing, and N is the ceiling on relay
  parallelism.
- **One relay per partition, enforced by a lock.** A relay takes a
  session-level `pg_try_advisory_lock` on a partition before consuming it. At
  first one process holds every lock. Scaling out means more processes
  splitting the locks, and a dead process's locks free up for a standby. Two
  relays registered as the same consumer could otherwise both receive the
  same open batch and both publish it.
- **Order stays per source.** All events of a source land in one partition.
  With the per-source write lock and the ordering xid described in "Commit
  order within a source", `(xid, id)` order within a source equals commit
  order, so publishing each batch in `(xid, id)` order publishes each source
  in commit order. Events of different sources in the same batch carry no
  order promise. Every message still carries `seq`, so downstream can detect
  a gap.
- **Not one relay per aggregate.** There are far more aggregates than useful
  relays. Partitions provide the parallelism and `seq` provides the order.
- **No cooperative subconsumers** for ordered delivery. Splitting one batch
  across workers without keeping a source on one worker breaks per-source
  order.

### Changing the partition count

Never change N without draining. If a source moves to a new partition while
its old partition still holds unpublished events, two relays can publish that
source out of order. Choosing N large at the start is what makes this rare.

`Trogon.Outbox.Migration.up/1` guards against the common accident: calling it
again with a different `:partitions` after the outbox is already installed
raises instead of silently keeping the old count. It does not perform the
drain itself, since the partition count is baked into the `partition` column
through a Postgres function set once at install time, not something the
migration can change in place. Passing the same count it was installed with
remains a no-op, so idempotent migration runs still work.

`Trogon.Outbox.Repartition.change!/3` performs the drain-checked swap in
place, without the "pause writes, or move sources over one at a time" an
operator would otherwise have to do by hand. It refuses while any event is
still unpublished, the same check `Retention` uses to decide whether a day is
safe to drop, run across every partition instead of one day. Closing the gap
between that check and the swap itself needs more than a check: it takes an
`ACCESS EXCLUSIVE` lock on `outbox_sources` first, the table every `append/4`
writes to first, which blocks every new append and waits for one already
running to finish before the functions are replaced in the same transaction.
Nothing can append under the old count once the precondition has passed, and
nothing appends under a half-changed one, so every event a source has before
the swap is published before it has any event after, and per-source order
survives the count changing underneath it.

`outbox_partition/1` is `IMMUTABLE`, which lets the planner inline it into a
caller's query at plan time; replacing it with `CREATE OR REPLACE FUNCTION`
rather than drop and recreate keeps its OID, and Postgres invalidates every
cached plan depending on that OID, so the next `append/4` on any connection,
prepared statement or not, replans against the new definition. There is no
connection left running on the old count after `change!/3` commits.

What it does not do: make a relay that is already running pick up the new
partitions. A relay's partition set is read once at start, so every relay
needs restarting after `change!/3` commits; one left running keeps serving
only the partitions it already held, silently missing whatever source now
hashes into a partition it never picked up.

`test/trogon/outbox/postgres_outbox/repartition_test.exs` proves the refusal
while unpublished, the block against a writer already appending, and that a
drained swap loses nothing, duplicates nothing, and keeps seq order for a
source whose events straddle the count change.

### The broker contract

- **Finish a batch only after the broker acknowledges every message in it.**
  A crash before that replays the whole batch.
- **Every message carries a stable id built from `source` and `seq`,** so
  consumers deduplicate replays, whatever the broker.
- **Every message carries `source` as its ordering key,** so the broker can
  keep a source's events together.

### No poison events by construction

An event cannot become poison. Only the environment, a broker down, a
misconfigured exchange, a message too large for the broker to ever accept,
can stall a partition, and that always alerts instead of skipping or
dropping the event that triggered it.

`Trogon.Outbox.append/4` validates a payload against a
`Trogon.Outbox.Publisher.Limits.t()` before it ever writes a row, so a
payload the configured publisher could never deliver never commits; the
caller gets an `ArgumentError` instead of an event sitting in the outbox
forever. `:limits` defaults to `Trogon.Outbox.Publisher.Limits.default/0`,
RabbitMQ 4's broker default `max_message_size` of 16 MiB. A publisher that
enforces a different limit implements the optional `limits/1` callback on
`Trogon.Outbox.Publisher`, returning a `Limits.t()` built from the same
options `publish/2` is called with, so `append/4` can be configured with the
identical limit: `Trogon.Outbox.Publishers.RabbitMQ.limits/1` builds one from
`:max_payload_size`. The limit is a value object, not a bare integer, so it
carries its own validation and cannot be confused with an unrelated size
somewhere else in the call.

The limit's own ceiling needs checking against the broker it will actually
publish to, not only against the configured number: `Limits.
check_broker_max_message_size!/2` raises before anything starts if the
broker's `max_message_size` is smaller than the configured limit, since a
payload under the configured limit but over the broker's would still be
rejected at publish time no matter how carefully `append/4` validated it.
RabbitMQ does not expose `max_message_size` over AMQP 0-9-1, so this is a
config-time check against a value the operator supplies, not something read
from the broker; document the broker's actual setting next to wherever
`:max_payload_size` is configured.

The backlog's full list of append-time rules also named a routing key under
255 bytes, header types, and encoding. A routing key depends only on the
partition and the configured `:routing_key` function, never on an event, so
checking every partition's key once when the relay starts, with
`Trogon.Outbox.Publishers.RabbitMQ.validate_routing_keys!/2`, covers every
event the relay will ever read; it is not a per-append check because nothing
about an individual event can make a routing key too long. Header types and
encoding are satisfied by construction today: `Trogon.Outbox.Event` carries
only a raw `payload :: binary()`, and the RabbitMQ publisher sets no
user-supplied headers on a publish, so there is nothing yet for either rule
to validate. This is a scope boundary, not a guarantee that outlives the
day a header or a non-binary payload is introduced; revisit both rules if
either lands.

A publish failure is classified before it is reported, `:temporary` for one
a retry alone fixes (a nack, a confirm timeout, the connection being down)
or `:environmental` for one that needs an operator, such as a message no
exchange or alternate exchange could route, or a payload over the
configured limit. An unrecognized failure defaults to `:environmental`
rather than `:temporary`, because alerting on a failure a retry would have
fixed costs an operator a look, while silently retrying a failure that
never resolves on its own costs a stalled partition nobody is told about.
The relay retries either classification with the same backoff and never
skips ahead on its own; the classification is only a signal for alerting,
never a reason to treat one kind of failure differently from the other in
the relay's own flow. `Trogon.Outbox.Publishers.RabbitMQ` reports both under
`[:trogon, :outbox, :publish, :failure]`.

### Publishing to RabbitMQ

`Trogon.Outbox.Publishers.RabbitMQ` publishes a batch on one channel, opened
and closed per batch on the connection
`Trogon.Outbox.Publishers.RabbitMQ.Connection` holds. The connection holder
reconnects on loss, so the relay keeps retrying through a broker restart
without ever publishing on a dead connection.

- **Acknowledgement.** Every event in the batch is published before the
  channel waits for a publisher confirm once, covering the whole batch,
  instead of confirming event by event. The broker round trip is paid per
  batch, not per event; see "Benchmarks" for the difference this makes. The
  stable id, built from `source` and `seq`, goes in `message_id`, so a
  redelivered duplicate still carries the same `message_id`. A nack, a
  confirm timeout, or the connection being down all return an error instead,
  so the relay retries the batch.
- **Unroutable messages.** The mandatory flag makes the broker return any
  event with no matching queue instead of silently dropping it. A return for
  a given message is not guaranteed to reach the channel before its confirm,
  so the publisher waits a short grace period after every confirm for a
  return before concluding the batch is routed. An `:alternate_exchange`
  gives the broker somewhere to route a message the configured exchange
  cannot: the broker tries the alternate exchange before concluding a
  mandatory message is unroutable, so a message bound to nothing on the
  primary exchange is caught instead of blocking the relay, as long as
  something is bound to the alternate exchange to receive it. This needs no
  change to the mandatory-return handling above, since the alternate
  exchange is tried entirely on the broker side, before a `basic.return`
  would ever fire; without `:alternate_exchange` an unroutable message still
  blocks the batch exactly as before. The default exchange cannot declare
  an `alternate-exchange` argument, so configuring both raises a config
  error before any connection is opened.
- **Order inside RabbitMQ.** The default routing key is one queue per
  partition, so one publisher on one channel keeps order per queue, which
  matches the per-source commit order the relay already reads in. Order
  still breaks on the consuming side: several consumers on one queue, or a
  reject and redelivery, reorder messages. Keeping order on the consuming
  side needs a quorum queue with a single active consumer, so only one
  consumer ever reads a given queue at a time; a classic queue with several
  consumers, or any consumer that requeues out of order, reorders
  deliveries regardless of how carefully the publisher preserved order.
- **Broker-side deduplication.** RabbitMQ Streams deduplicate on the
  publisher side using a producer name and publishing id. That needs checking
  against the RabbitMQ version in use before relying on it; this package
  deduplicates on `message_id` instead, which works against any queue type.

Proof: `test/trogon/outbox/postgres_outbox/publishers/rabbit_mq_test.exs`,
against a real broker, gated behind `TROGON_OUTBOX_RABBITMQ_URL`. It proves an
unroutable message does not advance the cursor, a broker restart does not
advance the cursor and the batch is redelivered once reconnected, per-source
order holds across a relay restart, and a redelivered duplicate carries the
same `message_id`.
`rabbit_mq_alternate_exchange_test.exs` proves a message the primary exchange
cannot route is captured instead of blocking the relay once
`:alternate_exchange` is configured, and still blocks exactly as before
without it. `rabbit_mq_telemetry_test.exs` proves the classification and
metadata of `[:trogon, :outbox, :publish, :failure]`.

### Other brokers, later

These are notes for when SQS or Kafka become targets, not part of the
current design.

- **SQS.** Only FIFO queues keep order, per message group. `source` maps to
  the message group id and the stable id to the deduplication id, which SQS
  honors only within a five-minute window. A replay after a longer outage
  needs consumer-side deduplication anyway.
- **Kafka.** Order holds per topic partition. Keying each record on `source`
  keeps a source on one partition, and an idempotent producer with
  `acks=all` avoids duplicates and reordering from producer retries.
  Changing the topic's partition count remaps keys, which is the same
  draining problem as changing N.

"The relay" proves the partitions, the lock per partition, takeover, and the
replay of an unacknowledged batch. "Publishing to RabbitMQ" proves the
RabbitMQ contract; the other brokers' notes are not proven.

## What to monitor

- Age of the oldest open transaction with an assigned transaction id anywhere
  on the cluster (`pg_stat_activity.backend_xid`), which holds back the
  watermark. `Relay.health/1`'s `watermark_holdback_ms` and the
  `[:trogon, :outbox, :watermark, :holdback]` event report this already,
  keyed on `backend_xmin` rather than `backend_xid`: the column set once a
  backend's transaction has taken the snapshot that counts against the
  xmin horizon, which is the mechanism actually doing the holding back.
- Replication slot lag, when delivering through logical decoding.
- Dead tuples and autovacuum frequency on `outbox_streams`.
- Number of attached partitions, so retention keeps up.
- Per-partition cursor lag, the distance between the newest event and the
  published cursor. `Relay.health/1`'s `lag` and the
  `[:trogon, :outbox, :cursor, :lag]` event report this already, per held
  partition, along with the age of the oldest unpublished event.
- Partitions without a relay holding their lock. The relay emits
  `[:trogon, :outbox, :lock, :acquired]` and `[:trogon, :outbox, :lock, :lost]`
  as these happen; `Relay.health/1` compares `held` against `expected` for a
  point-in-time read, worth alerting on when a partition is missing from
  `held` for longer than a few `:lock_interval`s.
- Time between a batch's tick and the broker acknowledging it.
- `pg_stat_io`, broken down by `backend_type`, for read and write amplification
  on the events, sources, and cursors tables, particularly `hit` versus `read`
  for the counter and cursor rows the relay and writers touch on every call.

## Direction

Start with an append-only, time-partitioned events table, a per-source counter
row tuned for heap-only tuple updates, a cursor table, a snapshot watermark on
reads, hash-partitioned single-consumer publishers, and no `NOTIFY` in the
business transaction. "What is implemented" describes that starting point as
it exists in this package. Move delivery to `pg_logical_emit_message` and logical
decoding only when insert throughput on the table becomes the bottleneck.

PgQue implements the ticks, insert-only events, and rotation already. It is
the candidate for the storage and batching underneath the partitioned relay,
pending proofs of per-source order across concurrent writers, rollback
handling, dead tuples after rotation, batch replay after a crash, partition
lock handover, and the effect of a long open transaction on delivery.
