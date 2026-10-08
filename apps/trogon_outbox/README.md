# Trogon.Outbox

Transactional outbox pattern for Elixir.

`Trogon.Outbox` appends events inside your Ecto transaction and publishes
them through a relay, in commit order per source, with a gapless seq. It is
early and its API may still change.

- [Use the outbox](docs/how-to/use-the-outbox.md)

The design is backed by tests that run against a real Postgres database and
prove where common outbox relay designs fall short, written up as
explanations:

- [Ordering gaps in a transactional outbox relay](docs/explanations/ordering-gaps.md)
- [Oban as a transactional outbox relay](docs/explanations/oban-as-an-outbox-relay.md)
- [Designing a Postgres outbox for order without contention](docs/explanations/postgres-outbox-design.md)

## Running the tests

The tests need a real Postgres database, `localhost:5432` with user and
password `postgres` by default. Point them elsewhere with
`TROGON_OUTBOX_DATABASE_URL`:

```sh
TROGON_OUTBOX_DATABASE_URL=ecto://postgres:postgres@db.example:5432/trogon_outbox_test mix test
```
