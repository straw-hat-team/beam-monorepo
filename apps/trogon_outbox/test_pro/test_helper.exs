alias Trogon.Outbox.ObanPro.Migrations
alias Trogon.Outbox.ObanPro.TestRepo

database_url =
  System.get_env(
    "TROGON_OUTBOX_OBAN_PRO_DATABASE_URL",
    "ecto://postgres:postgres@trogon-outbox-pg.orb.local:5432/trogon_outbox_pro_test"
  )

Application.put_env(:trogon_outbox, TestRepo, url: database_url, pool_size: 20, log: false)

{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto_sql)

case Ecto.Adapters.Postgres.storage_up(TestRepo.config()) do
  :ok -> :ok
  {:error, :already_up} -> :ok
end

{:ok, _pid} = TestRepo.start_link()

Ecto.Migrator.run(
  TestRepo,
  [{1, Migrations.AddOban}, {2, Migrations.AddObanPro}, {3, Migrations.AddUnindexedPrefix}],
  :up,
  all: true,
  log: false
)

Trogon.Outbox.ObanPro.Counter.init()

ExUnit.start(exclude: [:pro_behavior_changed])
