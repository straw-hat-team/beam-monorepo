database_url =
  System.get_env(
    "TROGON_OUTBOX_DATABASE_URL",
    "ecto://postgres:postgres@localhost:5432/trogon_outbox_test"
  )

Application.put_env(:trogon_outbox, Trogon.Outbox.TestRepo,
  url: database_url,
  pool_size: 10,
  backoff_min: 50,
  backoff_max: 1_000
)

Application.put_env(:trogon_outbox, Trogon.Outbox.TestSupport.SecondRepo, url: database_url, pool_size: 2)

{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)

case Ecto.Adapters.Postgres.storage_up(Trogon.Outbox.TestRepo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

{:ok, _pid} = Trogon.Outbox.TestRepo.start_link()

Ecto.Adapters.SQL.query!(Trogon.Outbox.TestRepo, "DROP TABLE IF EXISTS outbox_jobs")

Ecto.Adapters.SQL.query!(Trogon.Outbox.TestRepo, """
CREATE TABLE outbox_jobs (
  id bigserial PRIMARY KEY,
  source text NOT NULL,
  state text NOT NULL,
  payload text,
  created_at timestamp without time zone NOT NULL DEFAULT now()
)
""")

Ecto.Adapters.SQL.query!(
  Trogon.Outbox.TestRepo,
  "CREATE INDEX outbox_jobs_source_id_index ON outbox_jobs (source, id)"
)

oban_migration = [{Trogon.Outbox.TestSupport.ObanMigration.version(), Trogon.Outbox.TestSupport.ObanMigration}]
Ecto.Migrator.run(Trogon.Outbox.TestRepo, oban_migration, :up, all: true, log: false)

ExUnit.configure(exclude: [:chaos])
ExUnit.start()
