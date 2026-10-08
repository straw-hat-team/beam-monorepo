# Use the outbox

This guide installs the outbox tables, appends events inside a business
transaction, and runs a relay that publishes them. It assumes an Ecto repo on
Postgres 17 or later, here `MyApp.Repo`, with `trogon_outbox` in your
dependencies. Postgres 17 is the floor because a writer role needs
`transaction_timeout` to bound how long an open transaction can hold back the
relay, on top of retention needing `DETACH PARTITION ... CONCURRENTLY` since
Postgres 14. `Trogon.Outbox.Migration.up/1` and `Trogon.Outbox.Relay` both
check the connected server's version and raise instead of running against an
older one.
[Designing a Postgres outbox](../explanations/postgres-outbox-design.md)
explains why it works the way it does.

## Install the tables

Generate a migration and call `Trogon.Outbox.Migration` from it:

```elixir
defmodule MyApp.Repo.Migrations.AddOutbox do
  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(partitions: 64)
  def down, do: Trogon.Outbox.Migration.down()
end
```

`:partitions` is fixed at install time and caps how many relays can share the
work. Choose it generously, because changing it later means draining every
partition first. Pass `prefix: "outbox"` to both calls to keep the tables in
their own schema, and pass the same prefix to every call below.

## Append in a transaction

Call `Trogon.Outbox.append/4` inside the transaction that makes the business
change. The events commit or roll back with it:

```elixir
MyApp.Repo.transaction(fn ->
  order = MyApp.Repo.insert!(changeset)

  {:ok, [_event]} =
    Trogon.Outbox.append(MyApp.Repo, "order:#{order.id}", :erlang.term_to_binary({:placed, order.id}))

  order
end)
```

- The source, `"order:#{order.id}"` here, is the unit of ordering. Events of
  one source are published in commit order, each with the next seq. Pick the
  aggregate or stream the consumer needs in order, not something wider.
- Payloads are binaries. Pass a list to append several events of one source
  at once.
- Calling it outside a transaction raises.
- A payload over the configured publisher's limit raises instead of
  committing, so an event the publisher could never deliver never reaches
  the outbox. Pass `limits:` built from the same options the publisher
  uses, for example `Trogon.Outbox.Publishers.RabbitMQ.limits(max_payload_size: 1_000_000)`,
  so `append/4` enforces the same limit the relay's publisher will. Without
  it, `append/4` falls back to RabbitMQ 4's broker default `max_message_size`
  of 16 MiB.

Set `transaction_timeout` on every role that opens a business transaction
touching the outbox, for example in `postgresql.conf` or with `ALTER ROLE
app_writer SET transaction_timeout = '30s'`. An open transaction holds back
the snapshot watermark every relay reads behind, so one business transaction
left open stalls delivery for every source until it commits or rolls back.
`transaction_timeout` bounds that stall by terminating the session once its
current transaction has run longer than the limit. The outbox does not set it
for you: Postgres arms the timer from when the setting takes effect, not from
when the transaction actually started, so a `SET LOCAL` inside `append/4`
would only catch transactions that call `append/4` early enough, missing both
the transactions that never call it and the ones that call it late. A
role-level setting covers every transaction from the moment it starts.

## Write a publisher

A publisher sends one `Trogon.Outbox.Batch` to your broker and returns `:ok`
only once the broker has acknowledged all of it:

```elixir
defmodule MyApp.OutboxPublisher do
  @behaviour Trogon.Outbox.Publisher

  alias Trogon.Outbox.Event

  @impl true
  def publish(batch, opts) do
    channel = Keyword.fetch!(opts, :channel)

    Enum.each(batch.events, fn event ->
      MyApp.Broker.publish(channel, event.payload,
        message_id: to_string(Event.message_id(event)),
        ordering_key: to_string(event.position.source)
      )
    end)

    MyApp.Broker.wait_for_confirms(channel)
  end
end
```

`MyApp.Broker` stands for your broker client. Anything other than `:ok`
leaves the batch unpublished, and the relay retries the same batch with a
backoff. A crash between the broker's acknowledgement and the relay recording
it replays the batch, so consumers deduplicate on the message id, which is
`source:seq` and the same on every replay.

## Use the RabbitMQ publisher

`Trogon.Outbox.Publishers.RabbitMQ` implements the publisher behaviour above
for RabbitMQ, with publisher confirms, the mandatory flag, and a persistent
delivery mode. Add `:amqp` to your own dependencies, since it is optional for
`trogon_outbox`, then start a connection holder and pass it to the relay:

```elixir
children = [
  MyApp.Repo,
  {Trogon.Outbox.Publishers.RabbitMQ.Connection, url: System.fetch_env!("RABBITMQ_URL"), name: MyApp.RabbitMQ},
  {Trogon.Outbox.Relay,
   repo: MyApp.Repo,
   relay: "broker",
   publisher: {Trogon.Outbox.Publishers.RabbitMQ, connection: MyApp.RabbitMQ}}
]
```

The connection holder reconnects on loss, so the relay keeps retrying through
a broker restart instead of publishing on a dead connection. By default every
partition gets its own queue on the default exchange, which keeps publish
order equal to read order; pass `:routing_key` to route differently, and
`:exchange` to publish through something other than the default exchange.

Pass `:alternate_exchange` to catch a message `:exchange` cannot route
instead of leaving it as a blocking mandatory return; bind a queue to it to
keep what it catches. It needs `:exchange` set to a named exchange, since
the default exchange cannot declare one. Pass `:max_payload_size` to change
the limit the publisher enforces from RabbitMQ 4's broker default of 16
MiB; check it against the broker's actual `max_message_size` once at
startup with `Trogon.Outbox.Publisher.Limits.check_broker_max_message_size!/2`,
and validate every partition's routing key against AMQP's 255-byte limit
once with `Trogon.Outbox.Publishers.RabbitMQ.validate_routing_keys!/2`.

## Run a relay

Add a relay to your supervision tree:

```elixir
children = [
  MyApp.Repo,
  {Trogon.Outbox.Relay,
   repo: MyApp.Repo, relay: "broker", publisher: {MyApp.OutboxPublisher, channel: :orders}}
]
```

- The relay opens its own connection with the repo's configuration, so leave
  room for it in the database's connection limit.
- Run the same child on every node. One relay holds each partition at a time,
  and the others wait as standbys and take over when it dies.
- Give relays that publish to different destinations different `:relay`
  names. Each name keeps its own cursors and publishes every event. A relay
  name gets a row in the outbox's own registry table on first use, so lock
  collisions between unrelated relay names are not possible.
- To publish sooner after a commit than the polling backoff allows, call
  `Trogon.Outbox.Relay.poll/1` after the transaction commits. Do not send
  `NOTIFY` from inside the business transaction.

A relay's session advisory lock is released only when its connection's
backend actually disconnects, so a silent network partition that leaves the
TCP connection open without exchanging bytes keeps the lock held and blocks
every standby. Set `idle_session_timeout` on the relay's own connection to
bound that stall, since Postgres terminates the backend from its own clock
once the session has been idle past the limit, regardless of whether the
network is actually healthy:

```elixir
{Trogon.Outbox.Relay,
 repo: MyApp.Repo,
 relay: "broker",
 publisher: {MyApp.OutboxPublisher, channel: :orders},
 connection: [parameters: [idle_session_timeout: "30000"]]}
```

Size the limit above the relay's own poll interval plus normal query
latency; too tight a limit terminates an idle-but-healthy relay instead of a
stuck one.
[Designing a Postgres outbox](../explanations/postgres-outbox-design.md)
proves the bound against a frozen connection.

A transaction-mode connection pooler such as PgBouncer can hand the relay's
connection to a different backend between statements, separating its
session advisory lock from the relay that believes it holds it. Pass
`pooler_guard: true` to check for this at startup instead of only once it
happens during normal operation:

```elixir
{Trogon.Outbox.Relay,
 repo: MyApp.Repo,
 relay: "broker",
 publisher: {MyApp.OutboxPublisher, channel: :orders},
 connection: [hostname: "my-pgbouncer"],
 pooler_guard: true}
```

It is opt-in because checking means forcing the condition: a handful of
auxiliary connections through the same configuration keep the pool busy
while the relay's own connection is sampled, which opens connections of its
own and takes a moment, right as the relay is trying to start. `Trogon.Outbox.append/4`
needs no such guard and works through a transaction-mode pooler as is, since
it only ever runs inside a single transaction.
[Designing a Postgres outbox](../explanations/postgres-outbox-design.md)
proves both.

Attach a handler to watch lock changes, cursor lag, and watermark holdback
as they happen:

```elixir
:telemetry.attach_many(
  "broker-relay-logger",
  [
    [:trogon, :outbox, :lock, :acquired],
    [:trogon, :outbox, :lock, :lost],
    [:trogon, :outbox, :cursor, :lag],
    [:trogon, :outbox, :watermark, :holdback]
  ],
  &MyApp.RelayTelemetry.handle_event/4,
  nil
)
```

Cursor lag and watermark holdback fire on `:telemetry_interval`, 5000ms by
default:

```elixir
{Trogon.Outbox.Relay,
 repo: MyApp.Repo,
 relay: "broker",
 publisher: {MyApp.OutboxPublisher, channel: :orders},
 telemetry_interval: 10_000}
```

Call `Trogon.Outbox.Relay.health/1` with the relay's pid or registered name
for the same read on demand, without waiting for the next interval:

```elixir
Trogon.Outbox.Relay.health(pid)
```

[Designing a Postgres outbox](../explanations/postgres-outbox-design.md)
proves the telemetry events and `health/1` against a relay whose lock is
lost, a publisher that keeps failing, and an open transaction holding back
the watermark.

## Rotate partitions

Events are stored in one partition per day, created ahead by the migration.
Run `Trogon.Outbox.Retention` daily, for example from a scheduled job:

```elixir
:ok = Trogon.Outbox.Retention.create_partitions(MyApp.Repo, days_ahead: 7)

{:ok, %{dropped: _dropped, kept: _kept}} =
  Trogon.Outbox.Retention.drop_partitions(MyApp.Repo, before: Date.add(Date.utc_today(), -3))
```

An append fails when no partition exists for the current day, so keep
`:days_ahead` well above how often the job runs. `drop_partitions/2` keeps a
day that a relay has not fully published or that an open transaction can
still write to, and drops it on a later run. Dropping a day does not pause
appends to any other day, so this is safe to run on the same schedule as the
rest of the application's traffic.
