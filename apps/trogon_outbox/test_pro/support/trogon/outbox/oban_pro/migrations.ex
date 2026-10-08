defmodule Trogon.Outbox.ObanPro.Migrations.AddOban do
  @moduledoc false
  use Ecto.Migration

  @spec up() :: any()
  def up, do: Oban.Migration.up()

  @spec down() :: any()
  def down, do: Oban.Migration.down(version: 1)
end

defmodule Trogon.Outbox.ObanPro.Migrations.AddObanPro do
  @moduledoc false
  use Ecto.Migration

  @spec up() :: any()
  def up, do: Oban.Pro.Migration.up()

  @spec down() :: any()
  def down, do: Oban.Pro.Migration.down()
end

defmodule Trogon.Outbox.ObanPro.Migrations.AddUnindexedPrefix do
  @moduledoc """
  A second schema with the full Oban and Pro migrations but without the unique
  index, so an Oban instance pointed at it runs unique checks that are not
  backed by a unique index.
  """
  use Ecto.Migration

  @spec up() :: any()
  def up do
    Oban.Migration.up(prefix: "unindexed")
    Oban.Pro.Migration.up(prefix: "unindexed")
    execute("DROP INDEX IF EXISTS unindexed.oban_jobs_unique_index")
    execute("DROP INDEX IF EXISTS unindexed.oban_jobs_unique_index_old")
  end

  @spec down() :: any()
  def down do
    Oban.Pro.Migration.down(prefix: "unindexed", version: "1.0.0")
    Oban.Migration.down(prefix: "unindexed", version: 1)
  end
end
