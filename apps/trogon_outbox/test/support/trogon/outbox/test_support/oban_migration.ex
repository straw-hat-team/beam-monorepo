defmodule Trogon.Outbox.TestSupport.ObanMigration do
  @moduledoc false
  use Ecto.Migration

  @spec version() :: pos_integer()
  def version, do: 1

  @spec up() :: any()
  def up, do: Oban.Migration.up()

  @spec down() :: any()
  def down, do: Oban.Migration.down()
end
