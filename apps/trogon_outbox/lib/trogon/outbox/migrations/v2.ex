defmodule Trogon.Outbox.Migrations.V2 do
  @moduledoc false

  use Ecto.Migration

  alias Trogon.Outbox.Postgres

  @spec up(keyword()) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :prefix, "public")

    execute("""
    CREATE TABLE #{Postgres.relays(prefix)} (
      relay text PRIMARY KEY,
      id smallint NOT NULL GENERATED ALWAYS AS IDENTITY,
      UNIQUE (id)
    )
    """)

    :ok
  end

  @spec down(keyword()) :: :ok
  def down(opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    execute("DROP TABLE IF EXISTS #{Postgres.relays(prefix)}")
    :ok
  end
end
