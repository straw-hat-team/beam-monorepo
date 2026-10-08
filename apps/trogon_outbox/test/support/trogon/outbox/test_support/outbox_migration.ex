defmodule Trogon.Outbox.TestSupport.OutboxMigration do
  @moduledoc false

  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(prefix: prefix(), partitions: partitions())
  def down, do: Trogon.Outbox.Migration.down(prefix: prefix())

  def put_partitions(prefix, partitions), do: :persistent_term.put({__MODULE__, prefix}, partitions)

  defp partitions, do: :persistent_term.get({__MODULE__, prefix()}, 8)
end
