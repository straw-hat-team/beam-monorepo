defmodule Trogon.Outbox.PostgresOutbox.PostgresVersionTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: true

  alias Trogon.Outbox.PostgresVersion
  alias Trogon.Outbox.Relay
  alias Trogon.Outbox.TestSupport.OldPostgresSupport

  describe "supported?/1" do
    test "a version below 17.0 is not supported" do
      refute PostgresVersion.supported?(PostgresVersion.new!(169_999))
      refute PostgresVersion.supported?(PostgresVersion.new!(160_011))
    end

    test "17.0 and later are supported" do
      assert PostgresVersion.supported?(PostgresVersion.new!(170_000))
      assert PostgresVersion.supported?(PostgresVersion.new!(180_000))
    end
  end

  describe "ensure_supported!/1" do
    test "raises naming the required version and the server's reported version" do
      assert_raise ArgumentError, ~r/requires Postgres 17 or later.*server_version_num 160011/s, fn ->
        PostgresVersion.ensure_supported!(PostgresVersion.new!(160_011))
      end
    end

    test "does not raise at or above the minimum" do
      assert PostgresVersion.ensure_supported!(PostgresVersion.new!(170_000)) == :ok
    end
  end

  test "fetch!/1 reads the connected server's own version, which is at least 17" do
    version = PostgresVersion.fetch!(TestRepo)
    assert PostgresVersion.supported?(version)
  end

  if is_nil(OldPostgresSupport.url()) do
    @moduletag skip: OldPostgresSupport.skip_reason()
  end

  test "Migration.up/1 fails loudly against a Postgres older than 17", %{prefix: prefix} do
    repo = OldPostgresSupport.start_repo!()
    SQL.query!(repo, ~s(CREATE SCHEMA IF NOT EXISTS "#{prefix}"))

    assert_raise ArgumentError, ~r/requires Postgres 17 or later/, fn ->
      Ecto.Migrator.run(repo, [{1, Trogon.Outbox.TestSupport.OutboxMigration}], :up,
        all: true,
        prefix: prefix,
        log: false
      )
    end

    SQL.query!(repo, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE))
  end

  test "Relay.start_link/1 fails loudly against a Postgres older than 17" do
    repo = OldPostgresSupport.start_repo!()
    Process.flag(:trap_exit, true)

    result =
      Relay.start_link(
        repo: repo,
        relay: "old_pg",
        publisher: {Trogon.Outbox.TestSupport.TestPublisher, test_pid: self(), tag: "old_pg"}
      )

    assert {:error, reason} = result
    assert {%ArgumentError{message: message}, _stacktrace} = reason
    assert message =~ "requires Postgres 17 or later"
  end
end
