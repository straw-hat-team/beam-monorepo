defmodule Trogon.Outbox.PostgresOutbox.MigrationTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Migration
  alias Trogon.Outbox.TestSupport.RepartitionProbeMigration

  test "changing the partition count after install raises instead of silently keeping the old one", %{prefix: prefix} do
    RepartitionProbeMigration.put(prefix, 16)

    assert_raise ArgumentError, ~r/already installed with 8 partitions/, fn ->
      Ecto.Migrator.run(TestRepo, [{99, RepartitionProbeMigration}], :up, all: true, prefix: prefix, log: false)
    end

    assert Trogon.Outbox.partition_count(TestRepo, prefix: prefix) == 8
  end

  test "repeating the same partition count after install is a no-op", %{prefix: prefix} do
    RepartitionProbeMigration.put(prefix, 8)

    assert Ecto.Migrator.run(TestRepo, [{99, RepartitionProbeMigration}], :up, all: true, prefix: prefix, log: false) ==
             [99]

    assert Trogon.Outbox.partition_count(TestRepo, prefix: prefix) == 8
    assert Migration.migrated_version(TestRepo, prefix: prefix) == Migration.current_version()
  end
end
