defmodule Trogon.Ecto.MigrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Migration.Runner
  alias Ecto.Migration.Table

  defmodule StandardMigration do
    @moduledoc false
    use Trogon.Ecto.Migration
  end

  defmodule NoTransactionMigration do
    @moduledoc false
    use Trogon.Ecto.Migration, mode: :no_transaction
  end

  defmodule ConcurrentMigration do
    @moduledoc false
    use Trogon.Ecto.Migration, mode: :concurrent
  end

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
      {:ok, runner} =
        Runner.start_link(
          {self(), Trogon.Ecto.MigrationTest, [], __MODULE__, :forward, :up, %{level: false, sql: false}}
        )

      Runner.metadata(runner, [])

      on_exit(fn ->
        if Process.alive?(runner), do: Agent.stop(runner)
      end)

      %{runner: runner, table: %Table{name: "accounts"}}
    end

    defp add_command(runner, table, fun) do
      Runner.start_command({:alter, table})
      fun.()
      Runner.end_command()
      [command] = Agent.get(runner, & &1.commands)
      command
    end

    test "add_timestamp_column/2 adds a :timestamptz column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamp_column(:published_at)
        end)

      assert command == {:alter, table, [{:add, :published_at, :timestamptz, []}]}
    end

    test "add_timestamp_column/2 forwards caller opts", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_timestamp_column(:published_at, null: false)
        end)

      assert command == {:alter, table, [{:add, :published_at, :timestamptz, [null: false]}]}
    end

    test "add_timestamps/1 adds :inserted_at and :updated_at as :timestamptz", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
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
        add_command(runner, table, fn ->
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
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_stream_version_column()
        end)

      assert command == {:alter, table, [{:add, :stream_version, :bigint, [null: false]}]}
    end

    test "add_stream_version_column/1 lets caller opts override the default", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_stream_version_column(null: true)
        end)

      assert command == {:alter, table, [{:add, :stream_version, :bigint, [null: true]}]}
    end

    test "add_currency_code_column/1 adds a :currency_code :string column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_currency_code_column()
        end)

      assert command == {:alter, table, [{:add, :currency_code, :string, []}]}
    end

    test "add_money_amount_column/2 adds a :\"<name>_amount\" :integer column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_money_amount_column(:balance)
        end)

      assert command == {:alter, table, [{:add, :balance_amount, :integer, []}]}
    end

    test "add_annotations_column/1 adds an :annotations :map column defaulting to \"{}\"", %{
      runner: runner,
      table: table
    } do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_annotations_column()
        end)

      assert command == {:alter, table, [{:add, :annotations, :map, [default: "{}"]}]}
    end

    test "add_annotations_column/1 lets caller opts override the default", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_annotations_column(default: nil)
        end)

      assert command == {:alter, table, [{:add, :annotations, :map, [default: nil]}]}
    end

    test "add_uuid_column/2 adds a :binary_id column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_uuid_column(:external_id)
        end)

      assert command == {:alter, table, [{:add, :external_id, :binary_id, []}]}
    end

    test "add_object_id_column/2 adds a :string column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_object_id_column(:owner_id, null: false)
        end)

      assert command == {:alter, table, [{:add, :owner_id, :string, [null: false]}]}
    end

    test "add_union_object_id_column/2 adds a :string column", %{runner: runner, table: table} do
      command =
        add_command(runner, table, fn ->
          Trogon.Ecto.Migration.add_union_object_id_column(:account_id)
        end)

      assert command == {:alter, table, [{:add, :account_id, :string, []}]}
    end
  end
end
