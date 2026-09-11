defmodule Trogon.Ecto.MigrationTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.MigrationTestSupport
  alias Trogon.Ecto.MigrationTestSupport.ConcurrentMigration
  alias Trogon.Ecto.MigrationTestSupport.NoTransactionMigration
  alias Trogon.Ecto.MigrationTestSupport.StandardMigration

  describe "__using__/1" do
    test ":standard mode (the default) leaves the ddl transaction and migration lock enabled" do
      assert StandardMigration.__migration__() == [
               disable_ddl_transaction: false,
               disable_migration_lock: false
             ]
    end

    test ":no_transaction mode disables the ddl transaction only" do
      assert NoTransactionMigration.__migration__() == [
               disable_ddl_transaction: true,
               disable_migration_lock: false
             ]
    end

    test ":concurrent mode disables the ddl transaction and the migration lock" do
      assert ConcurrentMigration.__migration__() == [
               disable_ddl_transaction: true,
               disable_migration_lock: true
             ]
    end

    test "raises ArgumentError for an unknown mode" do
      assert_raise ArgumentError, ~r/unknown :mode :bogus/, fn ->
        Code.compile_quoted(
          quote do
            defmodule Trogon.Ecto.MigrationTest.UnknownModeMigration do
              use Trogon.Ecto.Migration, mode: :bogus
            end
          end
        )
      end
    end
  end

  describe "column helpers" do
    setup do
      MigrationTestSupport.start_migration_runner()
    end

    test "add_timestamp_column/2 adds a :timestamptz column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamp_column(:published_at)
        end)

      assert command == {:alter, table, [{:add, :published_at, :timestamptz, []}]}
    end

    test "add_timestamp_column/2 forwards caller opts", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamp_column(:published_at, null: false)
        end)

      assert command == {:alter, table, [{:add, :published_at, :timestamptz, [null: false]}]}
    end

    test "add_timestamps/1 adds :inserted_at and :updated_at as :timestamptz", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamps()
        end)

      assert {:alter, ^table, subcommands} = command

      assert subcommands == [
               {:add, :inserted_at, :timestamptz, [null: false]},
               {:add, :updated_at, :timestamptz, [null: false]}
             ]
    end

    test "add_timestamps/1 allows overriding the column names and type", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamps(inserted_at: :created_at, type: :utc_datetime)
        end)

      assert {:alter, ^table, subcommands} = command

      assert subcommands == [
               {:add, :created_at, :utc_datetime, [null: false]},
               {:add, :updated_at, :utc_datetime, [null: false]}
             ]
    end

    test "add_stream_version_column/1 adds a :bigint column defaulting to null: false", %{
      runner: runner,
      table: table
    } do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_stream_version_column()
        end)

      assert command == {:alter, table, [{:add, :stream_version, :bigint, [null: false]}]}
    end

    test "add_stream_version_column/1 lets caller opts override the default", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_stream_version_column(null: true)
        end)

      assert command == {:alter, table, [{:add, :stream_version, :bigint, [null: true]}]}
    end

    test "add_currency_code_column/1 adds a :currency_code :string column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_currency_code_column()
        end)

      assert command == {:alter, table, [{:add, :currency_code, :string, []}]}
    end

    test "add_money_amount_column/2 adds a :\"<name>_amount\" :integer column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_money_amount_column(:balance)
        end)

      assert command == {:alter, table, [{:add, :balance_amount, :integer, []}]}
    end

    test "add_string_map_column/2 adds a :jsonb column defaulting to \"{}\"", %{
      runner: runner,
      table: table
    } do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_string_map_column(:labels)
        end)

      assert command == {:alter, table, [{:add, :labels, :jsonb, [default: "{}"]}]}
    end

    test "add_string_map_column/2 lets caller opts override the default", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_string_map_column(:labels, default: nil, null: false)
        end)

      assert command == {:alter, table, [{:add, :labels, :jsonb, [default: nil, null: false]}]}
    end

    test "add_annotations_column/1 adds an :annotations :jsonb column defaulting to \"{}\"", %{
      runner: runner,
      table: table
    } do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_annotations_column()
        end)

      assert command == {:alter, table, [{:add, :annotations, :jsonb, [default: "{}"]}]}
    end

    test "add_annotations_column/1 lets caller opts override the default", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_annotations_column(default: nil)
        end)

      assert command == {:alter, table, [{:add, :annotations, :jsonb, [default: nil]}]}
    end

    test "add_uuid_column/2 adds a :binary_id column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_uuid_column(:external_id)
        end)

      assert command == {:alter, table, [{:add, :external_id, :binary_id, []}]}
    end

    test "add_object_id_column/2 adds a :string column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_object_id_column(:owner_id, null: false)
        end)

      assert command == {:alter, table, [{:add, :owner_id, :string, [null: false]}]}
    end

    test "add_union_object_id_column/2 adds a :string column", %{runner: runner, table: table} do
      command =
        MigrationTestSupport.capture_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_union_object_id_column(:account_id)
        end)

      assert command == {:alter, table, [{:add, :account_id, :string, []}]}
    end
  end
end
