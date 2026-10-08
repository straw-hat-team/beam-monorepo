# Oban as a transactional outbox relay

This explains what open source Oban does and does not give you when it is
used as the relay of a transactional outbox, and what has to be built on top
of it to close each gap. Every claim below was checked against the source of
Oban 2.24.1, the version locked in this repository, and every behavior is
proven by a test that runs real Oban queues against a real Postgres database.

## The relay being examined

The relay under examination inserts an Oban job in the same database
transaction as the business write. The job's args carry the event and the
source key it belongs to, typically an aggregate or stream id. A worker picks
the job up from a queue and publishes the event to a message broker. Oban
then records the outcome on the job row: `completed`, `retryable`,
`discarded`, and so on.

That shape is attractive because Oban already provides durable storage,
retries, scheduling, and a supervised execution model. The sections below
look at where those features stop short of what an outbox relay needs.

Each test under
[`test/trogon/outbox/oban_shortcomings/`](../../test/trogon/outbox/oban_shortcomings/)
starts one or more named Oban instances with `testing: :disabled`, so jobs
are fetched, executed, retried, and acknowledged by the same producers and
engine used in production.

## The insert is atomic with the business write

This one is a strength, not a shortcoming, and it is the reason Oban is a
reasonable starting point at all.

**The guarantee people assume.** An outbox exists so that the business write
and the record of the event to publish either both happen or neither does.
Teams worry that a job library sitting next to their schema behaves like an
external queue, where a rolled back transaction can still leave a message
behind.

**Why it holds.** `Oban.insert/3` with the default `Oban.Engines.Basic`
engine issues a plain insert into `oban_jobs` through the configured Ecto
repo. Called inside `Repo.transaction/2`, it runs on the transaction's
connection, and `Oban.insert/5` adds the insert as a step of an
`Ecto.Multi`. Either way the job row commits or rolls back with everything
else in the transaction.

**The test that proves it.**
[`insert_is_atomic_with_transaction_test.exs`](../../test/trogon/outbox/oban_shortcomings/insert_is_atomic_with_transaction_test.exs),
`"rolling back the business transaction also removes the job inserted inside
it"`, writes an outbox row, inserts a job, rolls back, and shows neither
exists afterwards. `"a failing step in an Ecto.Multi also removes the job
inserted earlier in it"` shows the same through `Ecto.Multi`, and
`"committing the business transaction keeps both the write and the job"`
shows the commit path leaves both in place.

**Direction of the fix.** Nothing to fix. Keep the insert inside the business
transaction and never move it to an after-commit hook, which would bring back
the dual-write problem the outbox exists to remove.

## Queue concurrency is per node, not per source

**The guarantee people assume.** Setting a queue's concurrency to 1 looks
like it serializes the queue, so events for the same source cannot be
published at the same time and cannot overtake each other.

**Why it does not hold.** `Oban.Engines.Basic.fetch_jobs/3` asks for
`limit - running` jobs, where `limit` and `running` belong to the local
producer, one per queue per Oban instance. It selects `available` jobs in the
queue ordered by `priority`, `scheduled_at`, and `id`, locked with
`FOR UPDATE SKIP LOCKED`. Nothing in that query looks at the args, so it has
no idea two jobs share a source, and the limit is enforced per node. Two
nodes running the same queue with a limit of 1 each run two jobs at once, and
those can be two consecutive events for the same source.

**The test that proves it.**
[`concurrent_same_key_execution_test.exs`](../../test/trogon/outbox/oban_shortcomings/concurrent_same_key_execution_test.exs),
`"two nodes with a limit of 1 each run two jobs for the same source at the
same time"`, starts two Oban instances with different node names against the
same database and queue, inserts two jobs for the same source, and shows both
are `executing` simultaneously, one on each node.

**Direction of the fix.** Serialize per source in the application. Take a
per-source lock (for example `pg_advisory_xact_lock` keyed on the source)
around the publish, or gate each job on its predecessor as described in
[Ordering gaps in a transactional outbox relay](ordering-gaps.md), and carry
a per-source sequence number so consumers can detect what the relay gets
wrong. Running a single node with a limit of 1 is not a fix, because it only
holds until the next deploy runs two nodes side by side.

## A retry lets a later event overtake an earlier one

**The guarantee people assume.** If the relay fails to publish an event, it
retries that event before moving on, so events for a source still go out in
insert order.

**Why it does not hold.** A failed job is acknowledged by
`Oban.Engines.Basic.error_job/3`, which moves it to `retryable` with a
`scheduled_at` in the future, and the queue moves on to the next `available`
job. The default `Oban.Worker.backoff/1` is
`Oban.Backoff.exponential(attempt, mult: 1, max_pow: 100, min_pad: 15)`
followed by `Oban.Backoff.jitter(mode: :inc)`, which works out to 15 seconds
plus 2 to the power of the attempt, plus up to 10% jitter, with the attempt
rescaled onto a 20-attempt curve when `max_attempts` is above 20. The default
`max_attempts` is 20. Every later job for the same source that is already
`available` runs during that window.

**The test that proves it.**
[`retry_backoff_reorders_test.exs`](../../test/trogon/outbox/oban_shortcomings/retry_backoff_reorders_test.exs),
`"a failed job retried after backoff lets a later job for the same source
publish first"`, runs a single queue with a limit of 1, fails the first event
once, and shows the second event is published before the first. `"the default
backoff waits at least 15 seconds plus 2 to the power of the attempt"` checks
the default backoff formula of a worker that does not override `backoff/1`.

**Direction of the fix.** Ordering has to survive retries, so the gate must
treat a `retryable` predecessor as blocking, not only `executing` and
`available` ones. A worker that sees an unfinished predecessor for its source
waits instead of publishing. Tuning backoff down only shrinks the window; it
does not close it.

## Delivery is at least once, not exactly once

**The guarantee people assume.** Once a job has published its event, it is
done, and the event will not be published again.

**Why it does not hold.** Oban records the outcome only after `perform/1`
returns. Anything that stops the job between the publish and that
acknowledgement leaves the job eligible to run again. A worker `timeout/1`
returning milliseconds makes `Oban.Queues.Executor` arm an exit timer that
kills the job with `Oban.TimeoutError`, which the producer treats as an
ordinary failure and retries. The default `timeout/1` is `:infinity`. A node
that shuts down waits `shutdown_grace_period` (15 seconds by default) for
running jobs, then leaves the rest in `executing` and lists them as
`orphaned` in the `[:oban, :queue, :shutdown]` telemetry event. Once rescued,
such a job runs its `perform/1` again from the start.

**The test that proves it.**
[`at_least_once_duplicate_publish_test.exs`](../../test/trogon/outbox/oban_shortcomings/at_least_once_duplicate_publish_test.exs),
`"a job that published and then timed out is retried and publishes the same
event again"`, publishes, outlives its timeout, and shows the same job
publishes again on its next attempt, with the `Oban.TimeoutError` recorded in
its errors. `"a job that published before its node shut down is left
executing and publishes again once rescued"` stops the Oban instance while the
job is running, shows the job is still `executing`, then starts a second
instance with Lifeline enabled and shows the same job publishes again.

**Direction of the fix.** Design for duplicates. Carry a stable event id in
the published message, derived from the outbox row rather than the job
attempt, and deduplicate on the consumer side, for example with a processed
events table keyed on that id inside the consumer's own transaction. Broker
side deduplication helps if the broker offers it, but only within its own
window.

## An orphaned executing job blocks its source until Lifeline runs

**The guarantee people assume.** If a node dies while running a job, the job
system notices and hands the job to another node.

**Why it does not hold.** Nothing watches `executing` jobs unless
`Oban.Lifeline` is configured, and `Oban.Config` does not start it by
default. Without it, an orphaned job stays `executing` forever, because
`fetch_jobs/3` only selects `available` jobs. With it, Lifeline runs every
`interval` (1 minute by default) on the leader node only, and
`Oban.Engines.Basic.rescue_jobs/3` moves every `executing` job whose
`attempted_at` is older than `rescue_after` (60 minutes by default) back to
`available`, or to `discarded` if it already used all its attempts. The
check is purely time based, so it cannot tell an orphan from a slow job that
is still running, and rescuing a live job runs it a second time in parallel.
Any per-source gate that waits on an unfinished predecessor waits behind the
orphan for as long as it stays `executing`.

**The test that proves it.**
[`lifeline_rescues_orphaned_executing_job_test.exs`](../../test/trogon/outbox/oban_shortcomings/lifeline_rescues_orphaned_executing_job_test.exs),
`"without Lifeline an orphaned executing job is never picked up again and its
successor waits behind it"`, orphans the head job of a source by shutting
down its node, then shows a second node keeps running the successor, which
keeps finding the orphan unfinished and snoozing, while the orphan stays
`executing` and attributed to the node that is gone. `"Lifeline moves an
orphaned executing job back to available after rescue_after and its
successor then proceeds"` repeats the setup with Lifeline enabled and shows
the orphan runs again and the successor publishes after it. `"Lifeline also
rescues a job that is still genuinely executing, so it runs twice at the same
time"` shows a job whose first run is still alive being started a second
time.

**Direction of the fix.** Always configure Lifeline for a relay, and set
`rescue_after` above the longest legitimate publish time, including the
worker `timeout/1`, so it rescues orphans without rescuing live jobs. Give
every worker a finite `timeout/1` so that bound actually exists. Alert on
jobs sitting in `executing` longer than expected and on the `orphaned` list
of the shutdown event, because until Lifeline acts every later event for that
source is stuck.

## Snoozing never runs out of attempts

**The guarantee people assume.** A chained worker that snoozes while its
predecessor is unfinished will eventually exhaust `max_attempts` and be
discarded, which at least surfaces the stall.

**Why it does not hold.** `Oban.Engines.Basic.snooze_job/3` moves the job to
`scheduled`, decrements `attempt`, and increments a `snoozed` counter in the
job's `meta`. The `Oban.Worker` documentation states that a snooze never
consumes an attempt. A gate built on `{:snooze, period}` therefore waits
indefinitely, and the job never reaches `discarded` because of it.

**The test that proves it.**
[`snooze_does_not_consume_attempts_test.exs`](../../test/trogon/outbox/oban_shortcomings/snooze_does_not_consume_attempts_test.exs),
`"a job with max_attempts 1 can snooze repeatedly without ever being
discarded"`, snoozes a job with `max_attempts: 1` several times, shows every
run reports attempt 1, and shows the job finally completes with
`meta["snoozed"]` counting every snooze.

**Direction of the fix.** Bound waiting explicitly. Read `meta["snoozed"]`
in the worker and, past a threshold, stop snoozing and raise an alert or move
the job to a held state that a human resolves, rather than letting a stuck
source wait silently.

## A discarded job is a lost event

**The guarantee people assume.** An outbox guarantees an event committed with
the business write is eventually published.

**Why it does not hold.** When a failing job has used its last attempt,
`Oban.Queues.Executor.normalize_state/1` marks the execution `:exhausted` and
`Oban.Engines.Basic.discard_job/2` moves the row to `discarded`. Nothing in
Oban retries a `discarded` job again on its own, and the only signal is a
`[:oban, :job, :exception]` telemetry event with `state: :discard`, which
does nothing unless the application attaches a handler. Later jobs in the
queue keep publishing, so the stream simply has a hole.

**The test that proves it.**
[`discard_after_max_attempts_test.exs`](../../test/trogon/outbox/oban_shortcomings/discard_after_max_attempts_test.exs),
`"a job that exhausts max_attempts is discarded and nothing delivers it
again"`, fails a job until it is discarded, observes the telemetry events,
then shows a later job in the same queue publishes while the discarded one
stays discarded and never publishes.

**Direction of the fix.** Treat `discarded` as a dead letter. Attach a
handler to `[:oban, :job, :exception]` for `state: :discard` that pages
someone, keep an operator path to retry the job once the cause is fixed (for
example `Oban.retry_job/2`), and decide per stream whether later events for
the same source may proceed past the hole, as discussed under ignore policies
in [Ordering gaps in a transactional outbox relay](ordering-gaps.md#ignore-policies-turn-a-lost-event-into-a-silent-gap).
Raising `max_attempts` delays the discard, it does not remove it.

## The jobs table is not an outbox log

**The guarantee people assume.** Since every event passes through
`oban_jobs`, the table doubles as the outbox log, useful for replaying events
to a new consumer or auditing what was published.

**Why it does not hold.** `oban_jobs` is a work queue. `Oban.Pruner`, which
`Oban.Config` only starts when configured, deletes `completed` jobs whose
`scheduled_at`, `cancelled` jobs whose `cancelled_at`, and `discarded` jobs
whose `discarded_at` is older than `max_age`, which defaults to 60 seconds,
checked every 30 seconds, up to 10,000 jobs per run. Running without the
pruner is not a real option either, because the table and its indexes keep
growing. Either way, published and lost events alike disappear on a schedule
that has nothing to do with how long consumers need them.

**The test that proves it.**
[`pruner_deletes_completed_jobs_test.exs`](../../test/trogon/outbox/oban_shortcomings/pruner_deletes_completed_jobs_test.exs),
`"completed and discarded jobs older than max_age are deleted, leaving
nothing to replay or audit"`, completes one event, discards another, ages
both past the default `max_age`, and shows the pruner deletes both while a
recently completed job remains.

**Direction of the fix.** Keep the outbox row as its own table, written in
the same transaction, with a retention policy chosen for replay and audit,
and let the Oban job reference it by id. The relay publishes from the outbox
row and marks it published; pruning the job then loses nothing.

## Unique jobs are not idempotency

**The guarantee people assume.** Inserting jobs with `unique` options keyed
on the event id means each event is enqueued, and therefore published, at
most once.

**Why it does not hold.** Uniqueness is a check at insert time over a window,
not a property of the event. The defaults in `Oban.Job` are `fields: [:args,
:queue, :worker]`, `period: 60` seconds measured on `inserted_at`, and
`states: :successful`, which `Oban.Job.unique_states/1` expands to
`suspended`, `available`, `scheduled`, `executing`, `retryable`, and
`completed`. A matching job outside that window, or in `discarded` or
`cancelled`, does not count, so the duplicate is inserted. `unique: true`
only changes the period to `:infinity`. On top of that,
`Oban.Engines.Basic.insert_job/3` takes `pg_try_advisory_xact_lock` for the
unique key, and when another open transaction already holds it, it returns an
unsaved job marked `conflict?: true` without inserting anything. If that
other transaction then rolls back, neither transaction leaves a job behind,
even though one of them committed its business write.

**The test that proves it.**
[`unique_jobs_are_not_idempotency_test.exs`](../../test/trogon/outbox/oban_shortcomings/unique_jobs_are_not_idempotency_test.exs),
`"a duplicate is rejected while the original is still in a unique state"`
shows the baseline dedupe. `"a duplicate is accepted once the original is
discarded, because discarded is not a default unique state"` and `"a
duplicate is accepted once the default 60 second period has passed"` show a
duplicate getting through once the original leaves the unique states or the
window closes. `"a unique insert that races an open transaction is
reported as a conflict and lost when that transaction rolls back"` holds one
transaction open after its unique insert, shows a second transaction's insert
comes back as a conflict with no id, rolls the first back, and shows no job
exists at all.

**Direction of the fix.** Do not use unique jobs to enforce once-only
delivery, and avoid them entirely on the insert that sits in the business
transaction, where the lock race can drop an event. Enforce uniqueness where
it is durable: a unique constraint on the outbox row's event id, and
consumer-side deduplication on the same id, as described under at-least-once
delivery above.

## Args are JSON, not Elixir terms

**The guarantee people assume.** The event handed to `insert` is the event
the worker publishes.

**Why it does not hold.** `Oban.Job` stores `args` in a `:map` field backed
by a `jsonb` column. The changeset returned from `insert` still holds the
original terms in memory, which makes the round trip look lossless, but the
worker receives whatever came back from JSON: atom keys and atom values
become strings, integer map keys become strings, and structs such as
`DateTime` become their JSON encoding with the struct gone.

**The test that proves it.**
[`args_json_round_trip_test.exs`](../../test/trogon/outbox/oban_shortcomings/args_json_round_trip_test.exs),
`"args reach perform/1 as decoded JSON, not as the terms that were
inserted"`, inserts a payload with an atom value, a `DateTime`, and an
integer-keyed map, shows the inserted job still reports the original terms,
and shows `perform/1` receives strings in their place.

**Direction of the fix.** Define the event's wire format explicitly. Encode
the payload yourself into a documented, versioned shape before it reaches
the outbox, decode it in the worker or the consumer with an explicit schema,
and store only JSON-native values in args, ideally just the outbox row id.

## Priority overrides insert order

**The guarantee people assume.** Events for a source leave the queue in the
order they were inserted, whatever other options the jobs carry.

**Why it does not hold.** `Oban.Engines.Basic.fetch_jobs/3` orders available
jobs by `priority`, then `scheduled_at`, then `id`. Priority is the first
sort key, so an event inserted later with a lower priority number is fetched
ahead of an earlier event for the same source, even on a single node with a
limit of 1.

**The test that proves it.**
[`priority_reorders_test.exs`](../../test/trogon/outbox/oban_shortcomings/priority_reorders_test.exs),
`"a later event with a higher priority publishes before an earlier event for
the same source"`, inserts two events into a paused queue with a limit of 1,
the later one with priority 0 and the earlier one with priority 3, resumes the
queue, and shows the later event publishes first.

**Direction of the fix.** Use a single priority for every job of a relay
queue, or route events that need different urgency to separate queues whose
sources never overlap. The per-source gate described under retries closes
this as well, because it ignores how jobs were fetched.

## A cancelled job is a lost event too

**The guarantee people assume.** Cancelling a job is an operational action
that pauses an event, not one that deletes it from the stream.

**Why it does not hold.** `Oban.cancel_job/2` moves the job to `cancelled`
and sets `cancelled_at`. Nothing in Oban runs a `cancelled` job again unless
someone calls `Oban.retry_job/2`, and later jobs for the same source keep
publishing. A cancelled outbox job leaves the same hole as a discarded one,
and the Pruner deletes it on the same schedule.

**The test that proves it.**
[`cancelled_job_is_lost_test.exs`](../../test/trogon/outbox/oban_shortcomings/cancelled_job_is_lost_test.exs),
`"a cancelled job is never published while later events for its source still
are"`, cancels a scheduled event, inserts a later event for the same source,
and shows the later one publishes while the cancelled one stays `cancelled`.

**Direction of the fix.** Treat cancellation of a relay job like a discard:
alert on it, keep the outbox row as the record of the event, and only allow
cancellation through an operator path that also decides what happens to the
source's later events.

## A node without the worker module fails the job

**The guarantee people assume.** During a rolling deploy, a job enqueued by
the new release waits until a node that knows its worker picks it up.

**Why it does not hold.** Any node running the queue can fetch any job in
it. `Oban.Queues.Executor.resolve_worker/1` calls `Oban.Worker.from_string/1`,
and when the module is not loaded on that node the execution is a failure
with `unknown worker` as the error. The job goes to `retryable` with the
default backoff, so later events for the same source publish ahead of it,
and when it has no attempts left it is discarded like any other failure.

**The test that proves it.**
[`unknown_worker_during_deploy_test.exs`](../../test/trogon/outbox/oban_shortcomings/unknown_worker_during_deploy_test.exs),
`"a node without the worker module fails the job into backoff while a later
event publishes"` inserts a job for a worker that does not exist on the
running node, shows it becomes `retryable` with an `unknown worker` error and
a `scheduled_at` in the future, and shows a later event publishes in the
meantime. `"a job for an unknown worker that has no attempts left is
discarded"` shows the same failure turning into a discard.

**Direction of the fix.** Keep the relay worker module stable across
releases and version the event payload instead of the worker. When a new
worker is unavoidable, ship it to every node before any node enqueues jobs
for it, or give it a queue that only upgraded nodes run.

## An Oban instance on a different repo breaks the insert's atomicity

**The guarantee people assume.** Calling `Oban.insert!/2` right next to the business write, before the surrounding transaction commits, inserts both the business row and the job atomically, no matter which named Oban instance handles the insert.

**Why it does not hold.** Every operation issued through `Oban.Repo` (`deps/oban/lib/oban/repo.ex`), including insert, dispatches to the `repo:` module configured on that specific instance's `Oban.Config`, through `with_dynamic_repo/2`. An `Ecto.Repo.transaction/2` only shares its checked-out connection with calls made through that same repo module on the calling process; a second `Ecto.Repo` module, even one pointed at the exact same database, checks out its own connection from its own pool and never sees the open transaction. An Oban instance started with `repo: SecondRepo` while the business write runs inside `TestRepo.transaction/1` commits the job the instant `Oban.insert!/2` returns, whether or not the surrounding transaction later rolls back.

**The test that proves it.**
[`different_repo_breaks_atomicity_test.exs`](../../test/trogon/outbox/oban_shortcomings/different_repo_breaks_atomicity_test.exs),
`"an Oban instance configured with a repo other than the one running the business transaction keeps the job after that transaction rolls back"` rolls the business write back and shows the job survives. `"the same setup committing the business transaction also keeps both the write and the job"` shows the matching success path, where both rows happen to survive only because nothing failed.

**Direction of the fix.** Configure the relay's Oban instance with the same `Ecto.Repo` module and prefix the business write uses, and treat a separate `repo:` option as a signal that insert-in-transaction atomicity has been given up, not assumed.

## The default retry window ends, and an outage longer than it discards the event

**The guarantee people assume.** A worker that keeps failing just keeps retrying until the broker or downstream comes back, so a temporary outage never loses an event as long as `max_attempts` stays at its default.

**Why it does not hold.** `Oban.Worker.backoff/1` (`deps/oban/lib/oban/worker.ex`) computes each retry's delay as `Oban.Backoff.exponential(attempt, mult: 1, max_pow: 100, min_pad: 15) |> Oban.Backoff.jitter(mode: :inc)`, and `max_attempts` defaults to `20`. Oban's own moduledoc (`deps/oban/lib/oban/worker.ex`) states the sum of that default schedule is "13 days and 8 hours" with jitter, after which attempt 20 fails and the job is discarded. An outage longer than that window outlives every scheduled retry, and the job that was supposed to carry the event forever disappears into `discarded` with no further attempt, while an event inserted for the same source after the outage ends publishes normally.

**The test that proves it.**
[`retry_window_exhaustion_test.exs`](../../test/trogon/outbox/oban_shortcomings/retry_window_exhaustion_test.exs),
`"the default backoff without jitter over 19 retries sums to the figure Oban's own docs round to 13 days with jitter"` computes the floor of that sum directly from `Oban.Backoff.exponential/2` and checks it against the documented total. `"an outage lasting the sum of every attempt's backoff discards the event while a later one for the same source still publishes"` runs a worker with a small `max_attempts` and a linear backoff to make the same failure mode observable in test time, and shows the discarded job stays discarded after a later event for the same source has already published.

**Direction of the fix.** Alert on the discard telemetry event well before the window closes, keep the source's own event id in a durable outbox table so it can be replayed after a discard, and treat an escalating alert, not a larger `max_attempts`, as the lever, since the window only grows logarithmically slower per extra attempt.

## scheduled_at can come from either clock, and an explicit one can reorder fetch ahead of insert order

**The guarantee people assume.** Jobs become available to run no earlier than when they were inserted, and `scheduled_at` is a server-side fact, immune to a calling node's clock being wrong.

**Why it does not hold.** When no scheduling option is given, `scheduled_at` is left out of the changeset and the Postgres column default in the `oban_jobs` migration (`deps/oban/lib/oban/migrations/postgres/v01.ex`), `default: fragment("timezone('UTC', now())")`, supplies it from the database server's own clock at insert time. But `Oban.Worker.new/2` accepts an explicit `:scheduled_at` (or `:schedule_in`/`:scheduled_in`, computed by `to_timestamp/1` at `deps/oban/lib/oban/job.ex` as `DateTime.add(DateTime.utc_now(), seconds, :second)`, the calling node's own clock) as a cast option, and `Oban.Engines.Basic.fetch_jobs/3` orders candidates `order_by(asc: :priority, asc: :scheduled_at, asc: :id)` (`deps/oban/lib/oban/engines/basic.ex`). A node whose clock reads behind real time can insert a later event with an earlier `scheduled_at` than one the database clock assigned moments before, and that later event is fetched first. A second effect falls out of the same code path: `Oban.Job.normalize_state/1` (`deps/oban/lib/oban/job.ex`) sets the initial state to `"scheduled"`, not `"available"`, whenever the changeset carries any `:scheduled_at` change at all, even one already in the past, so the job also waits on Oban's Stager to promote it before it can be fetched.

**The test that proves it.**
[`scheduled_at_clock_source_test.exs`](../../test/trogon/outbox/oban_shortcomings/scheduled_at_clock_source_test.exs),
`"a job inserted without a scheduling option has no scheduled_at in its changeset, so the database default supplies it at insert"` shows the changeset carries no `scheduled_at` change and the inserted row's timestamp falls inside the insert call's own wall-clock window. `"a later job with an explicit scheduled_at computed from a clock reading behind real time is fetched ahead of an earlier job that used the database clock"` inserts an earlier job with the database default and a later job with an explicit, skewed `scheduled_at`, confirms the skewed job starts `"scheduled"` rather than `"available"`, and shows it publishes first once both are eligible.

**Direction of the fix.** Avoid `:scheduled_at`, `:schedule_in`, and `:scheduled_in` on the outbox insert path entirely and let the database clock assign `scheduled_at`, or if a delay is required, source it from the database, for example `SELECT now()` run in the same transaction, rather than the application node's clock.

## A queue no running node declares, or one started paused, accumulates jobs with no error and no telemetry

**The guarantee people assume.** A misconfigured or paused relay queue surfaces itself through an error, a failed health check, or at least a telemetry event, so the gap gets noticed before events pile up.

**Why it does not hold.** `Oban.Registry` (`deps/oban/lib/oban/registry.ex`) is explicitly "Local process storage for Oban instances", so `Oban.check_queue/2` (`deps/oban/lib/oban.ex`) only sees producers registered on the calling BEAM node; for a queue no node in the whole cluster declares, it returns `nil` on every node, indistinguishable from asking about a queue that was simply never configured anywhere. A queue that is declared but started paused (`queues: [relay: [paused: true]]`) is visible through `check_queue/2`, which reports `paused: true`, but nothing in Oban emits telemetry for jobs sitting in it: insert telemetry fires once at insert time regardless of pause state, and nothing fires again until a job is fetched and executed, which a paused queue never does. Both cases leave `"available"` jobs accumulating indefinitely with no signal that distinguishes them from the healthy, empty-queue case.

**The test that proves it.**
[`unmonitored_queue_accumulates_silently_test.exs`](../../test/trogon/outbox/oban_shortcomings/unmonitored_queue_accumulates_silently_test.exs),
`"a queue that no running node declares accumulates available jobs with no error and no telemetry"` inserts a job for a queue the running node never configured and shows it stays `"available"` with `check_queue/2` returning `nil` and no telemetry received. `"a paused queue reports its state through check_queue but still accumulates jobs silently"` starts a queue already paused and shows the same silent accumulation, distinguishable only by querying `check_queue/2` for that specific queue name on that specific node.

**Direction of the fix.** Alert on a growing count of `"available"` jobs per queue rather than relying on Oban to surface a stuck queue, and treat `check_queue/2` returning `nil` across every node you can reach as a configuration error worth paging on, not a normal absence.

## Oban.insert_all/2 is atomic but silently ignores a worker's unique option

**The guarantee people assume.** A worker declared `unique: [...]` cannot produce duplicate jobs, whether it is inserted through `Oban.insert/2` one at a time or batched through `Oban.insert_all/2`.

**Why it does not hold.** `Oban.Engines.Basic.insert_job/2` checks uniqueness before inserting, but `insert_all_jobs/3` (`deps/oban/lib/oban/engines/basic.ex`) never calls that check: it maps every changeset through `Job.to_map/1` and issues a single `Repo.insert_all(conf, Job, jobs, on_conflict: :nothing, returning: true)`, so a worker's `unique` option is read by `Oban.Worker.new/2` and then simply discarded on this path. Oban's own documentation for the Basic engine states that only a commercial add-on's alternate engine honors `unique` on a batch insert, and that batching through the open source engine means giving up uniqueness, or inserting one at a time through `Oban.insert/2` instead.

**The test that proves it.**
[`insert_all_ignores_unique_test.exs`](../../test/trogon/outbox/oban_shortcomings/insert_all_ignores_unique_test.exs),
`"Oban.insert/2 rejects a unique duplicate but Oban.insert_all/2 inserts the same duplicate anyway"` inserts one job through `Oban.insert/2`, confirms a second identical insert through the same function is rejected as a conflict, then shows `Oban.insert_all/2` inserts two more copies of the exact same unique worker and args without complaint. `"insert_all inside the business transaction is atomic even though it ignores uniqueness"` shows the batch insert still rolls back cleanly with the business write, so atomicity and uniqueness are independent guarantees here.

**Direction of the fix.** Never batch unique workers through `Oban.insert_all/2`; insert them one at a time through `Oban.insert/2` so the unique check runs, or enforce the uniqueness constraint in the outbox table itself instead of relying on Oban for it.

## A queue that never gets a leader never stages a scheduled job

**The guarantee people assume.** A job whose `scheduled_at` has already passed becomes available to run on its own, as soon as any node's Stager plugin ticks.

**Why it does not hold.** `Oban.Stager.stage_and_notify/2` (`deps/oban/lib/oban/stager.ex`) only calls `Engine.stage_jobs/3`, the step that moves due `"scheduled"` and `"retryable"` jobs to `"available"`, when `Peer.leader?(state.conf)` is true for that tick; the non-leader clause (`deps/oban/lib/oban/stager.ex`) returns `{:ok, []}` without staging anything. `Oban.Peer`'s own moduledoc (`deps/oban/lib/oban/peer.ex`) states plainly that "without leadership, global plugins (Cron, Lifeline, Stager, etc.), will not run on any node." A cluster that never elects a leader, for example because the `oban_peers` table is unreachable or every node runs with `peer: false`, keeps ticking the Stager on every node, each one skipping the stage step, and a due job sits in `"scheduled"` forever with the exact same telemetry shape (`staged_count: 0`) as a healthy node that genuinely has nothing left to stage.

**The test that proves it.**
[`leaderless_stager_never_promotes_test.exs`](../../test/trogon/outbox/oban_shortcomings/leaderless_stager_never_promotes_test.exs),
`"a node that never becomes leader leaves a due scheduled job stuck at scheduled, with no error and no telemetry"` starts an instance with `peer: false`, inserts a job whose `scheduled_at` is already in the past, and shows it stays `"scheduled"` well past the Stager's own polling interval while the plugin's own telemetry reports a normal, zero-count tick.

**Direction of the fix.** Monitor `Oban.Peer.leader?/1`, or the age of the single row it maintains in `oban_peers`, directly, and alert when no node in the cluster holds leadership for longer than a few Stager intervals, since nothing else distinguishes that state from an idle, healthy queue.

## Queue control calls return :ok even when no node hears them

**The guarantee people assume.** `Oban.resume_queue/2` returning `:ok` means the queue is resumed, the same way `Oban.pause_queue/2`, `Oban.scale_queue/2`, `Oban.start_queue/2`, and `Oban.stop_queue/2` returning `:ok` mean their change took effect. A relay that pauses its queue during a broker outage, or resumes it after a deploy, relies on that.

**Why it does not hold.** Each of those functions (`deps/oban/lib/oban.ex`) builds a payload and hands it to `Notifier.notify/3` on the `:signal` channel, then returns whatever that returns. With the default `Oban.Notifiers.Postgres` (`deps/oban/lib/oban/notifiers/postgres.ex`), `notify` runs `pg_notify` through the repo, discards the query result, and returns `:ok`. A `NOTIFY` reaches only sessions that are listening at that moment, and nothing queues it for a listener that connects later. The notifier's own connection reconnects after a drop and issues `LISTEN` again, and `Oban.Queues` only registers for `:signal` in a `handle_continue/2` after its `init/1`, so there are windows, at boot and during every reconnect, in which a signal reaches nobody. `Oban.Notifier.status/1`'s own documentation says these functions "require a connected notifier to operate", but none of them checks it. `Oban.cancel_all_jobs/2`, and so `Oban.cancel_job/2`, uses the same channel to kill a job that is already executing, so a lost signal there leaves the job running after its row says `"cancelled"`.

**The test that proves it.**
[`queue_signal_lost_without_listener_test.exs`](../../test/trogon/outbox/oban_shortcomings/queue_signal_lost_without_listener_test.exs),
`"resume_queue returns :ok while the notifier is reconnecting, and the queue stays paused"` starts a paused queue, makes the test database refuse new connections with `ALLOW_CONNECTIONS false` so the notifier cannot reconnect early, terminates the notifier's listening backend with `pg_terminate_backend`, and calls `Oban.resume_queue/2` while no session is listening. The call returns `:ok`; once connections are allowed again the notifier reconnects, and `Oban.check_queue/2` still reports the queue paused. A second `resume_queue` after the reconnect resumes it, so the signal path itself works. `"cancel_job returns :ok while the notifier is reconnecting, and the executing job keeps running"` does the same to a job that has published and is still running: the call returns `:ok` and the row says `"cancelled"`, but the worker process is still alive after the reconnect and runs to the end. `"the same cancel_job with the notifier listening kills the executing job"` is the control.

**Direction of the fix.** Treat queue control as a request, not a command: after each call, read the result back with `Oban.check_queue/2` on every node that should run the queue and retry until it matches, or drive the desired state from configuration that each node applies locally at boot. Gate any operator tooling on `Oban.Notifier.status/1` before sending, and confirm cancellations of executing jobs by watching for the job's stop telemetry event rather than the row's state.

## A unique insert is dropped while another session holds an advisory lock with the same key

**The guarantee people assume.** A unique worker's insert either stores a new job or returns the existing job it conflicts with. A `conflict?: true` result means a matching job really exists.

**Why it does not hold.** `Oban.Engines.Basic.insert_unique/5` (`deps/oban/lib/oban/engines/basic.ex`) first calls `acquire_lock/2`, which runs `SELECT pg_try_advisory_xact_lock($1)`. The key is `:erlang.phash2(conf.prefix) + :erlang.phash2([keys, states, dynamic])`, so it is derived from the unique options and the values of the unique fields, and it lands in the same bigint advisory lock space every other piece of code on that database uses. When the lock is not granted, the `{:error, :locked}` branch builds a job from the changeset with `Changeset.apply_action/2`, marks it `conflict?: true`, and returns `{:ok, job}` without inserting anything and without checking whether a matching job exists. The lock can be held by a concurrent insert of the same job, which is the race already shown under unique jobs, but also by any unrelated session that took an advisory lock whose number happens to match, including a per-source lock taken by the relay itself.

**The test that proves it.**
[`unique_lock_key_collision_test.exs`](../../test/trogon/outbox/oban_shortcomings/unique_lock_key_collision_test.exs),
`"a unique insert is reported as a conflict and never stored while an unrelated session holds an advisory lock with the same key"` reads the key Oban uses for an event from `pg_locks`, takes that key with a plain `pg_advisory_xact_lock` in another session, and shows the insert returns `{:ok, %Oban.Job{id: nil, conflict?: true}}` while the table stays empty; once the other session releases its lock the same insert stores the job. `"the unique lock key lives in a space of at most 2 to the power of 28 values, far narrower than a bigint advisory lock"` shows every key read back stays below that bound.

**Direction of the fix.** Do not rely on Oban `unique` for an outbox event. Enforce uniqueness with a unique constraint on the event id in the outbox table, which Postgres resolves exactly, and keep any application advisory locks in a key range or a two-key form (`pg_advisory_xact_lock(int, int)`) that cannot meet Oban's single-key locks. Treat `conflict?: true` with `id: nil` as "not inserted".

## Unique replace overwrites a pending event instead of adding one

**The guarantee people assume.** Making a worker unique by source and passing `replace:` keeps the queue tidy by refreshing the pending job, and every event still gets published.

**Why it does not hold.** On a conflict, `resolve_conflict/4` (`deps/oban/lib/oban/engines/basic.ex`) looks up the keys listed for the existing job's current state in the `replace` option and updates that row with the new changeset's values for those keys. With `replace: [available: [:args]]`, a second event for the same source rewrites the args of the job that was waiting to carry the first event. The result is a single row, a `conflict?: true` reply, and no record anywhere that the first event's payload existed.

**The test that proves it.**
[`unique_replace_overwrites_pending_event_test.exs`](../../test/trogon/outbox/oban_shortcomings/unique_replace_overwrites_pending_event_test.exs),
`"a unique conflict with replace overwrites the args of a pending event, so only the later event is ever published"` inserts two events for one source into a paused queue, shows a single row carrying the later event's sequence, resumes the queue, and shows only the later event publishes.

**Direction of the fix.** Never combine `unique` and `replace` on a relay worker. Every event needs its own job, or better its own outbox row; coalescing belongs to the consumer, which can tell which version it last applied.

## When more jobs are due than the Stager limit, the newest are staged first

**The guarantee people assume.** Scheduled and retryable jobs become available in the order they fell due, so a backlog that builds up during an outage drains oldest first.

**Why it does not hold.** `Oban.Engines.Basic.stage_jobs/3` (`deps/oban/lib/oban/engines/basic.ex`) selects due `scheduled` and `retryable` jobs `order_by(desc: :scheduled_at, desc: :id)` with `limit: limit`, and `Oban.Stager` (`deps/oban/lib/oban/stager.ex`) passes a `limit` of `5_000` by default on each tick (1 second by default). When more jobs are due than the limit, a tick makes the most recently due ones available, the queue fetches and runs them, and the older ones wait for a later tick. A broker outage that leaves thousands of jobs in `retryable` is exactly the case that crosses the limit.

**The test that proves it.**
[`stager_limit_stages_newest_first_test.exs`](../../test/trogon/outbox/oban_shortcomings/stager_limit_stages_newest_first_test.exs),
`"when more jobs are due than the stager limit, the newest are staged and published first"` runs a Stager with a limit below the number of due jobs for one source and shows they publish in the order `[3, 4, 1, 2]`. `"with a stager limit above the number of due jobs, they publish in scheduled order"` shows the same jobs publish in order once the limit covers all of them.

**Direction of the fix.** Do not let the Stager decide order. The per-source predecessor gate has to treat every unfinished predecessor as blocking, whatever its state, and alerting on a `retryable` backlog approaching the Stager limit tells you when this path is live.

## Lifeline discards an orphan on its last attempt without an error

**The guarantee people assume.** A job that ends up `discarded` failed in its worker, so it has an error recorded and job exception telemetry fired, which is what dead-letter alerting listens to.

**Why it does not hold.** `Oban.Engines.Basic.rescue_jobs/3` (`deps/oban/lib/oban/engines/basic.ex`) moves stale `executing` jobs with `attempt >= max_attempts` straight to `discarded`, setting only `state` and `discarded_at`. The worker never runs again, nothing is appended to `errors`, and no `[:oban, :job, :exception]` or `[:oban, :job, :stop]` event fires for the job. The only trace is the `discarded_jobs` list in the Lifeline plugin's own `[:oban, :plugin, :stop]` metadata. A node that dies while a job is on its last attempt, including the first attempt of a `max_attempts: 1` worker, loses that event this way.

**The test that proves it.**
[`lifeline_discards_orphan_on_last_attempt_test.exs`](../../test/trogon/outbox/oban_shortcomings/lifeline_discards_orphan_on_last_attempt_test.exs),
`"an orphan on its last attempt is discarded by Lifeline without an error, a job exception, or another run"` orphans a `max_attempts: 1` job by stopping its node, starts a second node with Lifeline, and shows the job becomes `discarded` with an empty `errors` list, appears only in the Lifeline telemetry, never runs again, and does not stop a later event for the same source from publishing.

**Direction of the fix.** Feed dead-letter alerting from the Lifeline plugin's `discarded_jobs` metadata as well as from job exception events, or better, alert on any outbox event whose job reached `discarded` by reading the table, whatever path put it there.

## Retrying a discarded event puts it behind later events, and retry_all_jobs republishes completed ones

**The guarantee people assume.** The operator path for a discarded event is `Oban.retry_job/2` or `Oban.retry_all_jobs/2`, which puts the lost event back where it was and touches nothing else.

**Why it does not hold.** `Oban.Engines.Basic.retry_all_jobs/2` (`deps/oban/lib/oban/engines/basic.ex`) updates every matching job whose state is not `available` or `executing`, which includes `completed`, and sets `scheduled_at` to the current time. Since `fetch_jobs/3` orders by `priority`, `scheduled_at`, then `id`, a retried event is fetched after every later event already waiting in the queue. And a retry query scoped to a queue or worker, rather than to `state: "discarded"`, also sends every completed job in that scope back to `available`, so each of those events is published again.

**The test that proves it.**
[`retry_after_discard_reorders_test.exs`](../../test/trogon/outbox/oban_shortcomings/retry_after_discard_reorders_test.exs),
`"a discarded event retried while later events wait in the queue publishes after them"` discards the first event of a source, lets two later events queue up behind a paused queue, retries the first, and shows the publish order `[2, 3, 1]`. `"retry_all_jobs over a queue republishes events that already completed"` retries everything in the relay queue after one event was discarded and another completed, and shows both publish again, the completed one on a second attempt.

**Direction of the fix.** Scope every retry query to `state: "discarded"` and to the jobs you mean, and hold later events for the same source until the retried one publishes, which is the same predecessor gate the ordering sections call for. Consumers still need to deduplicate, because an over-broad retry is one query away.

## A leader that crashes keeps every other node from staging until its lease expires

**The guarantee people assume.** Leadership moves to a surviving node as soon as the leader dies, so the Stager and Lifeline keep running.

**Why it does not hold.** `Oban.Peers.Database` (`deps/oban/lib/oban/peers/database.ex`) holds leadership as a row in `oban_peers` with `expires_at` set `interval` after it was written, 30 seconds by default, and a leader renews it every half interval. Only a graceful `terminate/2` deletes the row and broadcasts that leadership is down. A node that is killed, runs out of memory, or loses its network leaves the row in place, and every other node's election keeps failing until the row's `expires_at` has passed and that node's next election, also on the 30 second interval, deletes it. Until then no node stages scheduled or retryable jobs and no node runs Lifeline.

**The test that proves it.**
[`crashed_leader_blocks_staging_test.exs`](../../test/trogon/outbox/oban_shortcomings/crashed_leader_blocks_staging_test.exs),
`"a leader that died without releasing its peer row keeps every surviving node from staging until the lease expires"` leaves a peer row behind for a node that no longer exists, starts a surviving node, and shows a due job stays `scheduled` and the survivor is not leader until the lease runs out, after which it takes over and the job publishes. `"a leader's peer row is written with a 30 second lease by default"` reads the lease a default leader writes.

**Direction of the fix.** Expect up to a lease plus an election interval without staging or rescue after a leader crash, and size alerting on scheduled and retryable backlogs with that in mind. Shortening the peer `interval` shortens the window at the cost of more writes to `oban_peers`.

## A fetch that keeps failing kills the jobs already running on that queue

**The guarantee people assume.** A database blip makes a queue stop picking up new work for a while, but jobs already running finish and record their outcome.

**Why it does not hold.** `Oban.Engines.Basic.fetch_jobs/3` runs inside `Oban.Repo.transaction/3`, which makes up to 5 attempts on a `Postgrex.Error` or `DBConnection.ConnectionError`, sleeping a growing delay between them, and then raises. The raise crashes the queue's producer, and `Oban.Queues.Supervisor` (`deps/oban/lib/oban/queues/supervisor.ex`) supervises the foreman `Task.Supervisor`, the producer, and the watchman with `strategy: :one_for_all`, so the restart also terminates the foreman and every job task it runs. A job that already published but had not been acknowledged is killed, its row stays `executing`, and it is published again only after Lifeline rescues it.

**The test that proves it.**
[`failing_fetch_kills_running_jobs_test.exs`](../../test/trogon/outbox/oban_shortcomings/failing_fetch_kills_running_jobs_test.exs),
`"a fetch that keeps failing crashes the producer and kills a job that had already published, leaving it executing"` starts a job that publishes and then waits, makes every fetch fail with a trigger that rejects the move to `executing`, inserts a second job to force a fetch, and shows the first job's process dies after the retries run out. Once fetching works again the restarted queue publishes the second job while the first stays `executing`.

**Direction of the fix.** Run every relay with Lifeline and consumer-side deduplication, because a database outage turns into orphaned jobs and duplicates, and keep publishes short so fewer are in flight when the queue restarts.

## Every job leaves dead tuples and index entries behind, and fetch reads them until vacuum

**The guarantee people assume.** A jobs table that holds few `available` rows is cheap to poll, however many jobs have gone through it.

**Why it does not hold.** Each job's life on the default migration is an insert, the fetch's update to `executing`, and the ack's update to `completed`. Both updates change `state`, which leads several indexes, including `oban_jobs_state_queue_priority_scheduled_at_id_index` that fetch scans, so neither can be a heap-only tuple update. Each one leaves a dead heap tuple and a new entry in every index on the table, and fetch keeps stepping over the stale `available` entries until vacuum removes them. Pruning completed rows only adds deletes on top.

**The test that proves it.**
[`job_lifecycle_bloat_test.exs`](../../test/trogon/outbox/oban_shortcomings/job_lifecycle_bloat_test.exs),
`"every published job costs at least two updates and none of them is a heap-only tuple update"` runs a batch of jobs through a real queue with autovacuum off for `oban_jobs` and shows, from `pg_stat_user_tables`, at least two updates per job, no heap-only updates, and at least one dead tuple per job. In local runs, 1,000 jobs produced 2,000 updates and 2,000 dead tuples. `"fetching from a queue with nothing available reads more index pages after jobs complete, until a vacuum"` runs the fetch query under `EXPLAIN (ANALYZE, BUFFERS)` before and after the batch and after a `VACUUM`, and shows the buffers read grow with the history and fall back after the vacuum.

**Direction of the fix.** Keep autovacuum aggressive on `oban_jobs`, for example a low `autovacuum_vacuum_scale_factor` for that table, watch `n_dead_tup` and fetch latency together, and keep long-running transactions off the database since they stop vacuum from removing anything. A dedicated outbox table whose relay advances a cursor instead of updating rows avoids most of this churn.

## An ack that loses its connection is retried until it lands

This one holds.

**The guarantee people assume.** If the database connection drops between a successful publish and the update that records it, the job is lost or left half done.

**Why it holds.** `Oban.Queues.Executor.call/1` (`deps/oban/lib/oban/queues/executor.ex`) wraps reporting the result in `Oban.Backoff.with_retry/1`, which retries database errors and timeouts with no upper bound on attempts, so the ack keeps trying until the pool has a working connection again.

**The test that proves it.**
[`ack_survives_connection_loss_test.exs`](../../test/trogon/outbox/oban_shortcomings/ack_survives_connection_loss_test.exs),
`"a job whose connections are all terminated between publish and ack is still completed once the database is reachable"` terminates every other backend of the test database after the worker publishes and before it returns, and shows the job is still `completed` on its first attempt with no second publish.

**Direction of the fix.** Nothing to fix for a short drop. An ack that waits on a long outage still holds a queue slot, and a node shut down during that outage leaves the job `executing`, which is the at-least-once case above.

## Oban.insert_all/2 keeps list order

This one holds.

**The guarantee people assume.** Events inserted in one batch keep the order of the list, both in the jobs returned and in the ids they get.

**Why it holds.** `insert_all_jobs/3` (`deps/oban/lib/oban/engines/basic.ex`) issues one multi-row `INSERT ... RETURNING`, and Postgres evaluates the id default row by row in the order of the values list. This is observed behavior of a single statement, not an ordering guarantee across concurrent transactions, so it does not close the commit order gap below.

**The test that proves it.**
[`insert_all_preserves_list_order_test.exs`](../../test/trogon/outbox/oban_shortcomings/insert_all_preserves_list_order_test.exs),
`"insert_all assigns ids and returns jobs in the order of the list it was given"` inserts a shuffled batch and shows both the returned jobs and the stored rows ordered by id follow the list.

**Direction of the fix.** Nothing to fix within one batch. Still assign the per-source sequence number yourself, because ids only reflect order inside one statement.

## Two different events can share a unique lock key, and the second is dropped

**The guarantee people assume.** Two unique inserts only get in each other's way when they describe the same job. Different events, with different unique field values, never conflict.

**Why it does not hold.** The advisory lock key built by `insert_unique/5` (`deps/oban/lib/oban/engines/basic.ex`) is `:erlang.phash2(conf.prefix) + :erlang.phash2([keys, states, dynamic])`. `:erlang.phash2/1` returns values below 2 to the power of 27, so by the birthday bound a colliding pair of events turns up after a few thousand distinct values. When two such events are inserted at the same time, the second one finds the key taken, is reported as `conflict?: true`, and is never stored, exactly as when an unrelated session holds the key.

**The test that proves it.**
[`unique_lock_hash_collision_test.exs`](../../test/trogon/outbox/oban_shortcomings/unique_lock_hash_collision_test.exs),
`"two different events whose unique lock keys collide cannot be inserted at the same time, and the second is dropped"` first searches for two event ids whose keys collide, by running Oban's own Basic engine against a stand-in repo that records the key instead of taking it. The hashed term embeds an `Ecto.Query.DynamicExpr` carrying the path Oban was compiled from, so the pair differs between builds and is found on every run rather than hardcoded; the search finishes in well under a second. The test then inserts the first event inside an open transaction, inserts the second from another session and gets `{:ok, %Oban.Job{id: nil, conflict?: true}}`, and shows that after the commit only the first event is stored, that the database saw the same key for both, and that inserting the second again once the lock is released stores it.

**Direction of the fix.** Do not use Oban uniqueness as the outbox's deduplication. Put a unique constraint on the outbox event id, where a conflict means a matching row really exists.

## A node clock that runs ahead rescues live jobs, lets duplicates in, prunes early, and steals leadership

**The guarantee people assume.** Oban's timing decisions run on the database clock, so the clocks of the application nodes do not matter.

**Why it does not hold.** Most of the cutoffs are computed on the node and sent as parameters. `rescue_jobs/3`, `prune_jobs/3`, and `since_period/3` in `deps/oban/lib/oban/engines/basic.ex` all start from `DateTime.utc_now()`, and so does `Oban.Peers.Database` (`deps/oban/lib/oban/peers/database.ex`) when it deletes peer rows whose `expires_at` has passed. The row timestamps they compare against were written by other nodes with their own clocks, or by the database. A node whose clock runs ahead sees every lease, rescue window, unique period, and retention age as older than it is.

**The test that proves it.**
[`node_clock_skew_test.exs`](../../test/trogon/outbox/oban_shortcomings/node_clock_skew_test.exs)
runs a second Oban instance through `Trogon.Outbox.TestSupport.SkewedClockRepo`, which shifts every timestamp the instance sends to the database, so Oban's own code runs unchanged while it reads a wrong clock.
`"a Lifeline leader whose clock runs ahead rescues a job that is well within rescue_after, so it runs twice"` starts a job on one node and a Lifeline leader 30 seconds ahead with a 10 second `rescue_after`, and shows a second attempt starts while the first is still alive; `"the same Lifeline leader with a correct clock leaves that job alone"` is the control.
`"a node whose clock runs ahead of the database by more than the unique period inserts a duplicate the other node rejects"` shows the node with a correct clock reports a conflict for an event that the node two minutes ahead then stores a second time.
`"a Pruner leader whose clock runs ahead by more than max_age deletes a job the moment it completes"` shows a completed job deleted at once under a 60 second `max_age`.
`"a node whose clock runs ahead by more than the peer lease deletes a live leader's lease and takes leadership"` leaves a live leader row with 30 seconds left, and shows a node 60 seconds ahead deletes it and becomes leader, while `"the same node with a correct clock waits for the live leader's lease"` does not.

**Direction of the fix.** Keep node clocks disciplined and alert on skew, and give an outbox relay timing decisions that the database clock makes, through `now()` in the query, rather than a parameter computed on the node.

## Behind a transaction pooler, queue control and cancellation stop working while every call returns :ok

**The guarantee people assume.** Putting a transaction mode pooler such as PgBouncer between the nodes and the database only changes how connections are shared.

**Why it does not hold.** `Oban.Notifiers.Postgres` (`deps/oban/lib/oban/notifiers/postgres.ex`) depends on `LISTEN`, which belongs to a server session, and its moduledoc states it "doesn't work with connection poolers like PgBouncer when configured in transaction or statement mode". The pooler hands each transaction to whichever server connection is free, so the session that ran `LISTEN` is not the one that receives a later `NOTIFY`. Every queue control call, and the kill signal for an executing job, travels over that channel, and none of them reports that nobody heard it.

**The test that proves it.**
[`transaction_pooler_test.exs`](../../test/trogon/outbox/oban_shortcomings/transaction_pooler_test.exs)
runs only when `TROGON_OUTBOX_PGBOUNCER_URL` points at a transaction mode pooler in front of the test database, and is skipped otherwise.
`"behind a transaction pooler the notifier never hears its own ping, so it reports itself isolated"` shows `Oban.Notifier.status/1` settles on `:isolated`.
`"behind a transaction pooler pause_queue returns :ok and the queue keeps publishing"` pauses the queue and shows a job inserted afterwards still publishes.
`"behind a transaction pooler cancelling an executing job marks it cancelled while it keeps running"` shows `Oban.cancel_job/2` returns `:ok` and the row says `"cancelled"` while the worker runs to the end.
`"named prepared statements and the transaction-scoped unique lock both work through the pooler"` holds: inserts, fetches, and the unique lock, which is transaction scoped, all behave as they do on a direct connection.

**Direction of the fix.** Connect the notifier, or the whole Oban repo, directly to the database, or use a notifier that does not depend on session state, such as `Oban.Notifiers.PG` over distributed Erlang. Check `Oban.Notifier.status/1` at boot and alert when it is not `:clustered` or `:solitary` as expected.

## Cron is neither exactly once nor catch-up

**The guarantee people assume.** A cron entry used to sweep the outbox, or to publish a periodic event, inserts exactly one job per scheduled minute.

**Why it does not hold.** `Oban.Cron` (`deps/oban/lib/oban/cron.ex`) evaluates the crontab in `handle_info(:evaluate, ...)`. It checks only `Peer.leader?/1`, matches the current minute from `DateTime.utc_now()`, inserts, and schedules the next evaluation. Nothing records which minutes were already inserted, so an evaluation that runs twice in one minute inserts twice, and a minute that passes while the node is not leader, because a stale peer row held leadership or the node was down, is never inserted by anyone once leadership arrives.

**The test that proves it.**
[`cron_ticks_are_not_exactly_once_test.exs`](../../test/trogon/outbox/oban_shortcomings/cron_ticks_are_not_exactly_once_test.exs),
`"a leader that evaluates the crontab twice within one minute inserts that minute's job twice"` sends `:evaluate` to the Cron plugin twice within the same minute and finds two jobs. `"a minute evaluated while the node is not leader is skipped, and gaining leadership does not catch it up"` keeps a live leader row for another node, evaluates, finds no job, removes the row so the node becomes leader, and still finds no job for that minute until the next evaluation.

**Direction of the fix.** Make the cron worker idempotent per scheduled minute, for example with a unique constraint on a minute key of your own, and do not rely on cron for anything that must run for every interval; let the swept work, not the tick, carry the state.

## A job killed after it published emits no stop or exception telemetry

**The guarantee people assume.** Every job that starts emits either `[:oban, :job, :stop]` or `[:oban, :job, :exception]`, so a publish counter built on those events matches what was published.

**Why it does not hold.** `Oban.Queues.Executor` (`deps/oban/lib/oban/queues/executor.ex`) emits the stop event only after the ack has been written. A job process killed between its publish and that point, by a shutdown that outlasts the grace period or by a crash of its producer, never reaches it. `Oban.Queues.Watchman` (`deps/oban/lib/oban/queues/watchman.ex`) reports the jobs it left behind in the `orphaned` metadata of `[:oban, :queue, :shutdown]`, but only on a graceful shutdown.

**The test that proves it.**
[`killed_job_has_no_stop_telemetry_test.exs`](../../test/trogon/outbox/oban_shortcomings/killed_job_has_no_stop_telemetry_test.exs),
`"a job killed by a shutdown after it published gets no stop or exception event, only an orphaned entry in the queue shutdown event"` stops a node while its job has published and is still running, and sees only the queue shutdown event naming that job. `"a job killed by a producer crash after it published emits no stop, exception, or queue shutdown event"` crashes the producer instead and sees nothing at all. `"a job that finishes before the shutdown emits its stop event"` is the control.

**Direction of the fix.** Count publishes where they happen, in the worker or the broker client, not from Oban's job events, and treat `orphaned` ids and jobs left `executing` as possibly published.

## Testing modes hide relay failures a running instance has

**The guarantee people assume.** Tests that use `testing: :inline` or `testing: :manual` with `Oban.drain_queue/2` exercise the same insert and publish behavior production has.

**Why it does not hold.** With `:inline`, `Oban.Engines.Inline` (`deps/oban/lib/oban/engines/inline.ex`) runs the job inside the insert call, before the surrounding transaction commits. With testing enabled, `insert_unique/5` skips `acquire_lock/2` (`deps/oban/lib/oban/engines/basic.ex`), so the advisory lock race never happens. `Oban.drain_queue/2` (`deps/oban/lib/oban/queues/drainer.ex`) fetches and runs jobs one at a time in the calling process, ignoring the queue's limit.

**The test that proves it.**
[`testing_modes_hide_relay_failures_test.exs`](../../test/trogon/outbox/oban_shortcomings/testing_modes_hide_relay_failures_test.exs),
`"with testing: :inline a job inserted in a transaction that then rolls back has already published"` shows a publish for an event whose business write rolled back.
`"with testing: :manual a unique insert is stored while its advisory lock key is held, where a running instance drops it"` holds the key a running instance needs, shows the running instance reports a conflict and stores nothing, and shows the manual instance stores the same event.
`"drain_queue runs jobs one at a time in insert order, so jobs a queue with a limit of 2 would overlap never do"` and `"the same jobs on a running queue with a limit of 2 overlap"` show the drained timeline is strictly sequential while the running queue starts both jobs before either finishes.

**Direction of the fix.** Keep at least one test path that runs a real queue with `testing: :disabled`, concurrent inserts, and the production queue limits, and assert ordering and duplicates there.

## Queue changes made at runtime are lost when the node restarts

**The guarantee people assume.** A queue paused during a broker outage, or scaled down to ease load, stays that way until someone changes it back.

**Why it does not hold.** `Oban.pause_queue/2` and `Oban.scale_queue/2` change the producer's in-memory state only (`deps/oban/lib/oban/queues/producer.ex`). A producer that starts reads its options from the node's configuration again, so a deploy, a crash, or a supervisor restart silently undoes the change.

**The test that proves it.**
[`runtime_queue_changes_lost_on_restart_test.exs`](../../test/trogon/outbox/oban_shortcomings/runtime_queue_changes_lost_on_restart_test.exs),
`"a queue paused at runtime publishes again as soon as its node restarts"` pauses a queue, inserts a job that does not publish, restarts the node, and sees it publish. `"a queue scaled down at runtime comes back at its configured limit after its node restarts"` scales a queue from 5 to 1 and finds it back at 5 after a restart.

**Direction of the fix.** Keep the desired queue state somewhere durable, such as a table or a feature flag, and apply it at boot and on change, rather than relying on runtime calls.

## A partitioned node's stale ack is rejected, but a lost fetch reply orphans a job

**The guarantee people assume.** A node that loses its connection to the database at the wrong moment either finishes its job correctly or leaves it for another node to run, and the telemetry it emits matches the row.

**Why it partly holds.** The ack in `Oban.Engines.Basic` (`deps/oban/lib/oban/engines/basic.ex`) matches the job's id, the `"executing"` state, and the `attempted_at` it fetched with, so a node that comes back after Lifeline rescued its job and another node fetched it again updates nothing. The node still emits a `:success` stop event, because the executor does not check how many rows the ack changed. The fetch is a transaction of its own, and when the reply to its `COMMIT` never arrives, the node treats the fetch as failed while the database has committed it, so the job sits in `executing` with no process running it.

**The test that proves it.**
[`network_faults_between_node_and_database_test.exs`](../../test/trogon/outbox/oban_shortcomings/network_faults_between_node_and_database_test.exs)
puts `Trogon.Outbox.TestSupport.TcpProxy` between one node and the database.
`"a stale ack from a partitioned node does not overwrite the rescued attempt running elsewhere, though that node reports success"` pauses the proxy while a job runs, lets a healthy node's Lifeline rescue and start a second attempt, finishes the first run, and resumes the proxy. The partitioned node emits a `:success` stop event, but the row is still `executing` on attempt 2 with the second attempt's `attempted_at`, and it completes only when that attempt does.
`"a fetch whose commit reply is lost leaves the fetched job executing with nothing running it, until Lifeline rescues it"` drops the connection right after the proxy forwards a fetch's `COMMIT`, and shows the job stays `executing` on attempt 1, attributed to that node, with nothing publishing it, until a node running Lifeline rescues it and attempt 2 completes.

**Direction of the fix.** Run Lifeline with a `rescue_after` above the longest publish, deduplicate on the consumer side, and do not treat a node's stop event as proof its ack landed.

## A large backlog does not slow the fetch, but large args do

The backlog half holds.

**The guarantee people assume.** A relay that falls behind gets slower to fetch as the backlog grows, and the size of each event's args does not matter.

**Why it holds, and where it does not.** The fetch in `Oban.Engines.Basic.fetch_jobs/3` (`deps/oban/lib/oban/engines/basic.ex`) selects `available` jobs for one queue in `priority`, `scheduled_at`, `id` order with `LIMIT` and `FOR UPDATE SKIP LOCKED`, which the composite index on `state`, `queue`, `priority`, `scheduled_at`, and `id` serves directly, so it touches only the rows it returns. It then returns every column of the rows it marks executing, so the args of every fetched job are read, detoasted, and sent to the node on each fetch. Postgres compresses large args through TOAST when they compress well, which shrinks storage but not the decoded value the node receives.

**The benchmark that shows it.** [`bench/oban_relay_bench.exs`](../../bench/oban_relay_bench.exs) runs Oban's own Basic engine fetch, with a limit of 10, inside a transaction it rolls back, against backlogs of `available` jobs and against jobs whose args hold a repetitive or a random payload. One run on Postgres 17.11 on a shared local server gave:

| available backlog | fetch p50 ms | fetch p90 ms | fetch max ms |
| --- | --- | --- | --- |
| 0 | 0.44 | 0.94 | 2.49 |
| 10000 | 0.71 | 0.99 | 206.47 |
| 100000 | 0.75 | 0.88 | 6.16 |
| 1000000 | 0.68 | 0.83 | 4.49 |

| args bytes | content | insert p50 ms | fetch of 10 p50 ms | stored bytes per row |
| --- | --- | --- | --- | --- |
| 1000 | repetitive | 11.56 | 0.82 | 1023 |
| 1000 | random | 23.35 | 0.99 | 1023 |
| 100000 | repetitive | 12.43 | 11.70 | 1178 |
| 100000 | random | 11.30 | 4.39 | 100019 |
| 1000000 | repetitive | 17.05 | 699.51 | 11474 |
| 1000000 | random | 13.80 | 64.80 | 1000019 |
| 10000000 | repetitive | 53.41 | 4023.37 | 114498 |
| 10000000 | random | 69.96 | 2564.85 | 10000019 |

The fetch stays under a millisecond at the median from an empty table to a million available jobs. Fetching 10 jobs with 1MB of args each takes tens to hundreds of milliseconds, and with 10MB each it takes seconds, and repeated runs vary by more than a factor of 1.5 at those sizes. Compressed repetitive args are the slowest to fetch even though they are the smallest on disk. The occasional 200ms outlier is the local network, not the query.

**Direction of the fix.** Keep relay args small: store the event payload in the outbox table and put only its id in the job, so the fetch moves ids and the publish reads the payload once.

**Against a running relay, not just a fetch.** [`bench/outbox_vs_oban_bench.exs`](../../bench/outbox_vs_oban_bench.exs) goes past the fetch and runs a real Oban OSS queue against `Trogon.Outbox.Relay`, same container, same writers, same duration. The outbox relay came out ahead on throughput and tail latency, and `oban_jobs` picked up close to two dead tuples per job inserted, where `outbox_events` picked up none, because the relay only ever reads its table while a job moves through states in place. The numbers, caveats, and what was and was not tried to take the client network out of the measurement are in [Postgres outbox design](postgres-outbox-design.md#against-oban-oss).

## A notify payload over 8000 bytes is silently dropped, and the call still returns :ok

**The guarantee people assume.** `Oban.Notifier.notify/3` returning `:ok`, including through `Oban.pause_queue/2`, `Oban.resume_queue/2`, `Oban.cancel_job/2`, and any application channel built on the same function, means Postgres accepted the notification and every listener will see it.

**Why it does not hold.** `Oban.Notifier.notify/3` (`deps/oban/lib/oban/notifier.ex`) encodes the payload with `Oban.Notifier.encode/1`, which gzips and base64 encodes it once it passes 512 bytes, then hands it to the configured notifier's `notify/3` and returns whatever that returns. `Oban.Notifiers.Postgres.notify/3` (`deps/oban/lib/oban/notifiers/postgres.ex`) runs `pg_notify` through the repo and discards the query result entirely, returning a hardcoded `:ok` whether the statement succeeded or Postgres raised an error. Postgres rejects any single `NOTIFY` payload over 8000 bytes with `payload string too long`, and compression only lowers the size for data that compresses well; a payload built from high entropy content, such as random identifiers, can stay over 8000 bytes encoded even at a few kilobytes of input.

**The test that proves it.** [`notifier_payload_limit_test.exs`](../../test/trogon/outbox/oban_shortcomings/notifier_payload_limit_test.exs), `"a notify payload over the 8000 byte Postgres limit still returns :ok, but Postgres rejects the NOTIFY and nothing is delivered"` sends a random payload confirmed by `Oban.Notifier.encode/1` to encode past 8000 bytes to a registered listener, shows the call returns `:ok` while the listener never receives anything, then shows a smaller payload on the same channel still arrives right after. `"a notify payload under the 8000 byte Postgres limit is delivered to a listener"` is the control.

**Direction of the fix.** Keep every payload sent through `Oban.Notifier.notify/3`, including any application channel built on it, well under 8000 bytes after encoding, and never read `:ok` as confirmation of delivery. Measure the encoded size before sending anything with unbounded content, such as a list of ids, through this channel.

## The unique period counts from insert, not from when a scheduled job becomes due

**The guarantee people assume.** A worker with `unique: [fields: [:args], keys: [...]]` and the default 60 second period keeps rejecting a duplicate for as long as the original job it would duplicate has not yet run.

**Why it does not hold.** `Oban.Engines.Basic.unique_query/1` (`deps/oban/lib/oban/engines/basic.ex`) builds the uniqueness check with `since_period(query, period, timestamp)`, and `Oban.Job`'s unique defaults (`deps/oban/lib/oban/job.ex`) set `timestamp: :inserted_at`, so the window is measured against when the row was written, not `scheduled_at`. A job inserted with an explicit `scheduled_at` or `schedule_in` further out than the unique period falls outside its own window before it is ever eligible to run: once `inserted_at` is older than `period`, a duplicate insert no longer finds it, even though the original is still sitting in `scheduled`, not `completed`, `discarded`, or `cancelled`.

**The test that proves it.** [`unique_period_ignores_scheduled_at_test.exs`](../../test/trogon/outbox/oban_shortcomings/unique_period_ignores_scheduled_at_test.exs), `"a duplicate is accepted once the default 60 second period has passed by inserted_at, even though the original is still scheduled and has not run"` inserts a job scheduled 120 seconds out, backdates its `inserted_at` by 61 seconds, and shows a second insert for the same unique key is accepted as a new job while the first is still `scheduled`. `"a duplicate scheduled far enough ahead is still rejected while the original's insert window has not closed"` is the control, showing the same pair deduped before the backdate.

**Direction of the fix.** Keep the unique period well above the longest `scheduled_at` delay any job in the worker uses, or set `timestamp: :scheduled_at` explicitly when combining `unique` with a future `scheduled_at`, so the window tracks when the job is due rather than when it was inserted.

## Integer precision survives the jsonb round trip, but key order does not survive storage

This one mostly holds.

**The guarantee people assume.** Since args pass through JSON, a large integer could lose precision the way it would through a JSON consumer that decodes numbers as floats, and the order object keys were written in could be scrambled by the time the worker reads them back.

**Why it holds, and where it does not.** Elixir integers have arbitrary precision, and `Jason.encode!`/`Jason.decode!`, which back `Oban.JSON` (`deps/oban/lib/oban/json.ex`) when the `JSON` module is not available, encode and parse integer literals as exact digit strings rather than floats, so an integer far beyond `2^53` round-trips through `args` exactly. Postgres's `jsonb` type does the same for numbers, storing them as exact text rather than a fixed-width type. `jsonb` does reorder an object's keys at the storage layer, by length and then alphabetically rather than insertion order, but that reordering is invisible to the application: `Oban.Job.args` is typed as a plain Elixir map on insert and comes back as a plain Elixir map in `perform/1`, and Elixir maps have no defined key order to begin with, so nothing that reads `args` as a map can observe the reorder.

**The test that proves it.** [`args_integer_precision_and_key_order_test.exs`](../../test/trogon/outbox/oban_shortcomings/args_integer_precision_and_key_order_test.exs), `"an integer well beyond 2^53 reaches perform/1 with full precision, not rounded by a float conversion"` inserts a 30 digit integer and shows it reaches `perform/1` unchanged and is stored as the same exact digit string. `"jsonb storage reorders an object's keys by length then alphabetically, but Oban.Job.args round-trips as a plain Elixir map, so the application never observes any order"` reads the stored row's keys directly with `jsonb_each` and shows they are not in insertion order, while the same job's `args` in `perform/1` still compares equal to the original map.

**Direction of the fix.** Nothing to fix through `Oban.Job.args`. The reorder would only matter if a key order were read from `args` by something other than map access, for example re-serializing args to recompute a signature taken before insert; avoid doing that, or encode an order-sensitive payload as a JSON array instead of relying on object key order.

## Id order is still not commit order

Oban job ids come from a `bigserial` sequence, so they inherit the gap
explained in
[Id order is not commit order](ordering-gaps.md#id-order-is-not-commit-order):
a transaction that takes a lower id can commit after one that took a higher
id. Ordering by job id, or by `scheduled_at`, has the same blind spot as the
`outbox_jobs` table examined there, and the fix is the same per-source lock
taken before the insert, plus a per-source sequence number assigned under it,
as described in
[A timestamp is not a sequence number](ordering-gaps.md#a-timestamp-is-not-a-sequence-number).

## What commercial add-ons change

Commercial add-ons for Oban offer features such as chained or partitioned
workers and global concurrency limits across nodes. Those target the per-node
concurrency gap above, but the predecessor-check approach they are typically
built on still has the gaps described in
[Ordering gaps in a transactional outbox relay](ordering-gaps.md): ordering
scoped to a source, ignore policies that skip lost events silently, and id
order that differs from commit order. None of those add-ons were tested here.

## Related explanations

The predecessor-check design that most ordering fixes above rely on, and the
places where it still breaks, are covered in
[Ordering gaps in a transactional outbox relay](ordering-gaps.md).

## Read in source, not proven here

**`Oban.Peers.Global` requires distributed Erlang, which this suite does not run.** `Oban.Peer`'s moduledoc (`deps/oban/lib/oban/peer.ex`) names `Oban.Peers.Global` as the other built-in peer implementation, coordinating leadership through global locks across connected BEAM nodes instead of the `oban_peers` table used by the default `Oban.Peers.Database`. Whether its leadership handoff behaves differently from the database peer during a real multi-node network split cannot be shown by starting two named Oban instances inside a single test node, so it is left undemonstrated.

**Instances with different prefixes share one advisory lock space.** The unique lock key adds `:erlang.phash2(conf.prefix)` to the hash of the unique fields rather than keeping a separate key space per prefix, so tenants on separate prefixes in the same database can collide with each other's unique inserts, and with any other advisory lock on that database, in the same way two events on one prefix do above. The mechanism is the one the collision test proves; a cross-prefix pair is not searched for.

**Behind a transaction pooler, some notifications still arrive.** When the session that ran `LISTEN` happens to be the server connection a later transaction runs on, that notification is delivered, so a pooler gives sporadic delivery rather than none. Whether a given signal arrives depends on the pooler's connection assignment, so only the isolated status and the lost pause and cancel are asserted.

**The notifier under load.** `Oban.Notifiers.Postgres` sends every notification with `pg_notify` and ignores the result, and Postgres keeps undelivered notifications in a queue of limited size, beyond which `NOTIFY` fails. A notifier that falls behind, or a listener that stops reading, could therefore lose or block signals under heavy insert traffic. Producing that deterministically depends on server settings and timing, so it is not tested here. The per-payload size limit this same mechanism runs into is proven above, separately from this load question.

**Peer, Stager, and Pruner do not take advisory locks at all, so there is no shared lock space between them to collide in.** A grep of `deps/oban/lib/` for `advisory_lock` turns up exactly one call site: `acquire_lock/2` inside `Oban.Engines.Basic.insert_unique/5` (`deps/oban/lib/oban/engines/basic.ex`), the uniqueness check proven above and in the lock key collision tests. `Oban.Peer` and its implementations (`deps/oban/lib/oban/peer.ex`, `deps/oban/lib/oban/peers/database.ex`, `deps/oban/lib/oban/peers/global.ex`) elect a leader through a row in `oban_peers` or through distributed Erlang globals, neither of which takes a Postgres advisory lock. `Oban.Stager` (`deps/oban/lib/oban/stager.ex`) and `Oban.Plugins.Pruner` (`deps/oban/lib/oban/plugins/pruner.ex`) run plain queries with no locking beyond the row locks their own `UPDATE`/`DELETE` statements take. The only other use of a hash in this neighborhood is `Oban.Cron`'s `:erlang.phash2` on a crontab entry, which picks a name for a registered process and never reaches Postgres. The hypothesis that Peer, Stager, and Pruner share an advisory lock space with each other, or collide with an application's own advisory locks the way two unique inserts can, does not hold: only the unique insert path takes an advisory lock, and the collision it is exposed to is the one already proven under unique jobs above.

**The Reindexer holds.** `Oban.Reindexer` (`deps/oban/lib/oban/reindexer.ex`) rebuilds its indexes with `REINDEX INDEX CONCURRENTLY` under a timeout and afterwards drops any `oban_jobs` index left invalid by an interrupted rebuild, so it does not block inserts or fetches and does not leave a broken index behind.

## Summary

| Shortcoming | Consequence | Required fix |
| --- | --- | --- |
| Queue concurrency is per node, not per source | Two events for the same source publish concurrently and out of order | Per-source lock or predecessor gate, plus a per-source sequence number |
| A retry lets a later event overtake an earlier one | A later event publishes while an earlier one waits out its backoff | Gate treats `retryable` predecessors as blocking |
| Delivery is at least once | Timeouts and node shutdowns republish events that already went out | Stable event id in every message and consumer-side deduplication |
| An orphaned executing job blocks its source | Without Lifeline the source stalls forever; with it, a live job can run twice | Configure Lifeline, finite worker timeouts, `rescue_after` above them, alerting |
| Snoozing never runs out of attempts | A waiting gate stalls silently instead of surfacing | Cap `meta["snoozed"]` and alert or hold past the cap |
| A discarded job is a lost event | The stream has a hole that nothing fills | Dead-letter alerting on the discard telemetry event and an operator retry path |
| The jobs table is not an outbox log | Pruning removes published and lost events alike | Separate outbox table with its own retention |
| Unique jobs are not idempotency | Duplicates pass after discard or the period, and a lock race can drop an event | Unique constraint on the outbox event id and consumer-side deduplication |
| Args are JSON | Atoms, integer keys, and structs do not survive the round trip | Explicit, versioned wire format with JSON-native args |
| Priority overrides insert order | A later event with a higher priority publishes first | One priority per relay queue, or the per-source gate |
| A cancelled job is a lost event | The stream has a hole that nothing fills | Alert on cancellation and keep the outbox row as the record |
| A node without the worker module fails the job | Rolling deploys reorder events and can discard them | Stable worker module, deploy workers before enqueueing for them |
| An Oban instance on a different repo breaks atomicity | The insert and the business write stop being atomic even though both calls look identical | Use the exact repo module and prefix the business transaction runs on |
| The default retry window ends | An outage longer than roughly 13 days discards the event for good | Alert well before the window closes and keep a durable, replayable record of the source event |
| scheduled_at can come from either clock | Node clock skew on an explicit scheduled_at can let a later event publish before an earlier one | Let the database clock assign scheduled_at instead of the application node |
| A queue no running node declares, or one started paused, accumulates jobs silently | Jobs pile up with no error or telemetry to notice by | Alert on growing available counts per queue and treat a universal nil from check_queue as a configuration error |
| Oban.insert_all/2 ignores a worker's unique option | Batch inserts can silently duplicate a unique worker's jobs | Insert unique workers one at a time through Oban.insert/2 |
| A queue that never gets a leader never stages a scheduled job | Due jobs sit in scheduled forever, indistinguishable from a healthy idle queue | Monitor Oban.Peer leadership directly and alert on its absence |
| Queue control calls return :ok even when no node hears them | A pause, resume, scale, or cancel of an executing job can be lost at boot or during a notifier reconnect, with nothing reported | Read the result back with Oban.check_queue/2 and retry, or apply queue state from local configuration |
| A unique insert is dropped while another session holds an advisory lock with the same key | An event is reported as a conflict and never stored | Unique constraint on the outbox event id, advisory locks kept out of Oban's key space |
| Unique replace overwrites a pending event | The earlier event's payload disappears | Never combine unique and replace on a relay worker |
| The Stager stages the newest due jobs first past its limit | A retry backlog drains newest first | Predecessor gate that blocks on every unfinished predecessor |
| Lifeline discards an orphan on its last attempt | The event is lost with no error and no job exception telemetry | Alert from Lifeline's discarded_jobs metadata or the table itself |
| Retrying a discarded event, or retrying too broadly | The retried event publishes after later ones, and completed events publish again | Scope retries to discarded jobs and gate later events behind the retried one |
| A crashed leader keeps its peer row | No node stages or rescues jobs for up to a lease plus an election interval | Size backlog alerts for that window, or shorten the peer interval |
| A fetch that keeps failing restarts the whole queue | Running jobs that already published are killed and left executing | Lifeline, consumer-side deduplication, short publishes |
| Every job lifecycle is non-heap-only updates | Dead tuples and index entries pile up and fetch reads them until vacuum | Aggressive autovacuum on oban_jobs, no long transactions, or a cursor-based outbox table |
| Id order is not commit order | Ordering by job id can publish a later commit first | Per-source lock before insert and a per-source sequence number |
| Two different events can share a unique lock key | Concurrent inserts of unrelated events drop one of them as a conflict | Unique constraint on the outbox event id instead of Oban uniqueness |
| A node clock that runs ahead | Live jobs are rescued and run twice, duplicates pass the unique period, completed jobs are pruned early, and a live leader loses its lease | Disciplined clocks with skew alerting, and database-side timestamps |
| A transaction pooler breaks the notifier | Pause, resume, scale, and cancellation of executing jobs are lost while every call returns :ok | Direct connection for the notifier, or a notifier without session state, and a status check at boot |
| Cron is neither exactly once nor catch-up | A minute can be inserted twice, or never | Idempotent cron workers keyed by the scheduled minute |
| A killed job emits no stop or exception telemetry | Publish counts built on job events undercount | Count publishes in the worker or broker client, and treat orphaned and executing jobs as possibly published |
| Testing modes hide relay failures | Tests pass on publishes after a rollback, missing lock races, and missing concurrency | A test path with testing disabled and production queue limits |
| Runtime queue changes are lost on restart | A paused or scaled down queue returns to its configured state on deploy | Durable desired queue state applied at boot |
| A lost fetch reply orphans a job, and a stale ack still reports success | A job sits executing with nothing running it, and telemetry disagrees with the row | Lifeline, consumer-side deduplication, and not trusting stop events as ack proof |
| Large args slow the fetch | Fetching jobs with megabytes of args takes hundreds of milliseconds to seconds | Keep the payload in the outbox table and only its id in the job |
| A notify payload over 8000 bytes is silently dropped | Queue control, cancellation, and any application channel on Oban.Notifier report :ok with nothing delivered | Keep encoded payloads well under 8000 bytes and never treat :ok as delivery |
| The unique period counts from inserted_at, not scheduled_at | A duplicate for a far-future scheduled job is accepted once the period elapses by insert time, while the original still has not run | Set unique timestamp: :scheduled_at, or keep the period above the longest scheduled_at delay |
