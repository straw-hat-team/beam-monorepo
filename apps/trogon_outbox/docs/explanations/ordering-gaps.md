# Ordering gaps in a transactional outbox relay

This explains where "ordered delivery" quietly breaks in a common transactional
outbox relay design, and why each break is a property of the design rather
than a bug in any particular implementation of it.

## The design being examined

The design under examination inserts an outbox row and a background job in
the same database transaction as the business write. Jobs are partitioned by
a source key, typically an aggregate or stream id. Some job libraries that
offer chained or sequential workers implement ordering this way: before a
worker publishes a job, it looks up the latest earlier job for the same
source with a query shaped like:

```sql
SELECT id FROM jobs
WHERE source = $1 AND id < $2 AND state != 'completed'
ORDER BY id DESC
LIMIT 1
```

If that predecessor is executing or pending, the worker waits or snoozes
itself and tries again later. If the predecessor is discarded or cancelled, a
policy decides what happens next: halt the source entirely, hold the current
job for manual intervention, or ignore the predecessor and let the current
job proceed. If there is no predecessor, the worker publishes to a message
broker.

Each test under
[`test/trogon/outbox/ordering_gaps/`](../../test/trogon/outbox/ordering_gaps/)
runs this exact predecessor query, or a direct model of the surrounding
behavior, against a real Postgres database and asserts that the gap
described below actually happens.

## Ignore policies turn a lost event into a silent gap

**The guarantee people assume.** When a job library offers a choice between
halting, holding, or ignoring a discarded or cancelled predecessor, picking
"ignore" sounds like it only affects the stuck job itself: the chain resumes
and later events keep flowing.

**Why it does not hold.** Ignoring a discarded or cancelled predecessor does
not fill in the event that predecessor represented. It was never published.
The consumer that was promised in-order delivery for that source receives
event two right after whatever it last saw, with no record that event one
ever existed. Nothing in the stream tells the consumer a gap occurred, because
from the consumer's point of view there never was a pending event one to miss,
only an event two that arrived.

**The test that proves it.**
[`skip_policy_test.exs`](../../test/trogon/outbox/ordering_gaps/skip_policy_test.exs),
`"an ignore policy publishes the next event even though its predecessor was
discarded"`, inserts a discarded job followed by a pending job for the same
source and shows the predecessor query decides to publish the pending job
with the ignore policy. The companion test, `"a hold policy blocks the next
event instead of letting it skip past the gap"`, runs the identical setup
with the hold policy and shows the decision changes to hold instead of
publish.

**Direction of the fix.** Treat "ignore" as a policy for jobs that have no
externally visible effect, not for ones that represent a domain event a
consumer is waiting on. For event streams, prefer hold or halt so a human
notices the gap before more events build on top of it, and reserve ignore for
chains where losing a link truly has no observable consequence downstream.

## Id order is not commit order

**The guarantee people assume.** Because the id column is a database
sequence, people assume a lower id was fully committed before a higher id,
so checking predecessors by id is equivalent to checking predecessors by
commit order.

**Why it does not hold.** A sequence hands out the next value at insert time,
not at commit time. Two concurrent transactions on the same source can have
transaction A take id 1 and transaction B take id 2, and then B can commit
first while A is still open. Under the default READ COMMITTED isolation
level, the predecessor query that runs for job 2 only sees committed rows, so
it does not see id 1 yet. It finds no predecessor and publishes. Only after
that does A commit, and its own predecessor query also finds nothing blocking
it, so it publishes too, after id 2 already went out.

**The test that proves it.**
[`id_order_vs_commit_order_test.exs`](../../test/trogon/outbox/ordering_gaps/id_order_vs_commit_order_test.exs),
`"a transaction that commits later can still be decided first, publishing out
of id order"`, holds one transaction open after its insert using a real
second process, inserts and commits a second row from a separate connection
in the meantime, and shows the publish order comes out as the higher id
first, then the lower id.

**Direction of the fix.** The companion test in the same file, `"an advisory
lock taken before insert serializes commits so id order matches commit
order"`, takes a `pg_advisory_xact_lock` keyed on the source before the
insert. That forces the second transaction to wait until the first one
commits, which makes id order and commit order coincide again, and the
publish order comes out in id order. A per-source row lock taken with
`SELECT ... FOR UPDATE` on a tracking row achieves the same serialization.

## Ordering is scoped to a source, not to the whole system

**The guarantee people assume.** Teams sometimes read "ordering is
guaranteed" as a system-wide property, expecting the relative order of any
two events to be preserved regardless of which source produced them.

**Why it does not hold.** The predecessor query filters by source on
purpose, so that one source's backlog does not stall every other source.
That is a reasonable design choice, but it means a source whose head job is
stuck executing, pending, or endlessly snoozing has no effect on any other
source's throughput. Events keep flowing for every unrelated source while one
source's queue backs up behind its stuck job. There was never a global
sequence to begin with, only independent per-source ones.

**The test that proves it.**
[`per_source_ordering_test.exs`](../../test/trogon/outbox/ordering_gaps/per_source_ordering_test.exs),
`"a stuck head on one source does not block delivery on another source"`,
leaves one source's first job executing forever, confirms its next job is
stuck waiting, and shows a second, unrelated source publishes its three
pending jobs in full while the first source stays blocked.

**Direction of the fix.** Do not advertise or rely on cross-source ordering.
If a consumer needs a total order across sources, it has to be built as a
separate concern, for example by assigning a single global sequence under a
single lock, which trades the per-source concurrency this design was built
to preserve.

## Ordering ends at publish

**The guarantee people assume.** Once a relay publishes events to a message
broker in the right order, people assume the consumer side handles them in
that same order.

**Why it does not hold.** A message broker with competing consumers
distributes deliveries across whichever consumer is free, which is a
throughput feature, not an ordering one. If one consumer happens to be slower
than another, for example because it is doing more work per message or is
under more load, in-order deliveries land on handlers that finish in a
different order than they were delivered. Publish order and handle order are
two different things, and only the first one is in the relay's control.

**The test that proves it.** This part is modeled, not integration tested
against a real broker:
[`broker_reordering_model_test.exs`](../../test/trogon/outbox/ordering_gaps/broker_reordering_model_test.exs),
`"round-robin dispatch to two consumers with different latency reorders
handling vs delivery (model of the transport, not a broker integration
test)"`, dispatches four in-order deliveries round robin across two plain
processes standing in for competing consumers, gives them different
processing latency, and shows the order in which they report handling the
deliveries differs from the order they were delivered in.

**Direction of the fix.** If handling order matters, route all messages for
the same source to a single consumer, for example through consistent-hash
partitioning or a single active consumer per source, so one slow handler
cannot let a later message for the same source overtake an earlier one. A
broker-level single active consumer per source, or a queue per source, both
work.

## A timestamp is not a sequence number

**The guarantee people assume.** A `created_at` column with a database
default seems like it should give consumers a stable way to order or
deduplicate events, since it looks like a wall-clock record of when each row
came into being.

**Why it does not hold.** Postgres' `now()` returns the start time of the
current transaction, not the time the current statement runs. Two rows
inserted in the same transaction get an identical `created_at`, so there is
no way to order between them. Worse, a transaction that starts earlier but
commits later gets a `created_at` that is earlier than a row from a
transaction that started later but committed first. A consumer that already
advanced its cursor to the second row's `created_at`, because that row was
delivered first, will never pick up the first row under a `created_at >
cursor` filter: the first row's timestamp now sits behind a cursor that has
already moved past it.

**The test that proves it.**
[`created_at_is_not_a_sequence_test.exs`](../../test/trogon/outbox/ordering_gaps/created_at_is_not_a_sequence_test.exs)
covers this from multiple angles. `"two inserts in the same transaction
share an identical created_at"` proves the first half of the claim directly.
`"a transaction
that starts first but commits last gets an earlier created_at than a row
already delivered"` reproduces the same held-transaction setup used for the
id-versus-commit-order gap, and shows the delivered row's `created_at` leaves
the first row permanently unreachable through a `created_at > cursor` filter.
`"a per-source sequence number lets a consumer detect a missing event that
created_at cannot"` runs a small pure gap-detection function against the
sequence numbers `[1, 3]` and shows it reports `2` as missing, something a
timestamp has no way to express because timestamps carry no notion of "the
value that should have come next."

**Direction of the fix.** Assign a per-source monotonic sequence number at
insert time, taken under the same per-source lock used to fix id order
versus commit order. Unlike a timestamp, a sequence number has a well-defined
successor, so a consumer that tracks the highest sequence number it has seen
per source can detect a missing one the moment a later one arrives, instead
of silently reordering or permanently dropping events around transaction
boundaries.

## Related explanations

A relay built on Oban specifically is exposed to the gaps above and adds its own,
from per-node concurrency limits and retries that reorder events to pruning
and at-least-once delivery. Those are covered in
[Oban as a transactional outbox relay](oban-as-an-outbox-relay.md).
