defmodule Trogon.Ecto.MigratorIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag capture_log: true

  alias Ecto.Adapters.Postgres
  alias Trogon.Ecto.Migrator
  alias Trogon.Ecto.TestSupport.IntegrationRepo

  @accounts 20_260_101_000_000
  @orders 20_260_102_000_000
  @profiles 20_260_103_000_000

  setup_all do
    config = IntegrationRepo.test_config()
    Application.put_env(:trogon_ecto, IntegrationRepo, config)
    _ = Postgres.storage_down(config)
    :ok = Postgres.storage_up(config)
    :ok
  end

  setup do
    start_supervised!(IntegrationRepo)

    for table <- ~w(accounts orders profiles schema_migrations) do
      IntegrationRepo.query!("DROP TABLE IF EXISTS #{table}")
    end

    dir = Path.join(System.tmp_dir!(), "trogon_migrator_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir}
  end

  describe "run/4" do
    test "runs every pending migration when none is older than the applied ones", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")

      assert Migrator.run(IntegrationRepo, [dir], :up, all: true) == [@accounts, @profiles]
      assert applied_versions() == [@accounts, @profiles]
      assert table_exists?("accounts")
      assert table_exists?("profiles")
    end

    test "runs migrations on a fresh database where the highest version is not first", %{dir: dir} do
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      write_migration!(dir, @accounts, "create_accounts", "accounts")

      assert Migrator.run(IntegrationRepo, [dir], :up, all: true) == [@accounts, @profiles]
      assert applied_versions() == [@accounts, @profiles]
    end

    test "refuses to migrate when a pending version is below the highest applied one", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Migrator.run(IntegrationRepo, [dir], :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")

      assert_raise Ecto.MigrationError, fn ->
        Migrator.run(IntegrationRepo, [dir], :up, all: true)
      end
    end

    test "leaves the database untouched when it refuses to migrate", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Migrator.run(IntegrationRepo, [dir], :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")

      assert_raise Ecto.MigrationError, fn ->
        Migrator.run(IntegrationRepo, [dir], :up, all: true)
      end

      assert applied_versions() == [@accounts, @profiles]
      refute table_exists?("orders")
    end

    test "names the stale migration and the version it has to clear", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Migrator.run(IntegrationRepo, [dir], :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")

      error =
        assert_raise Ecto.MigrationError, fn ->
          Migrator.run(IntegrationRepo, [dir], :up, all: true)
        end

      assert error.message =~ "20260102000000 create_orders"
      assert error.message =~ "above 20260103000000"
    end

    test "rolls back without checking the order, since down visits older versions", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Migrator.run(IntegrationRepo, [dir], :up, all: true)

      assert Migrator.run(IntegrationRepo, [dir], :down, step: 1) == [@profiles]
      assert applied_versions() == [@accounts]
      refute table_exists?("profiles")
    end
  end

  describe "check_version_order!/3" do
    test "passes on a database with nothing applied", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")

      assert Migrator.check_version_order!(IntegrationRepo, [dir], []) == :ok
    end

    test "reads the applied versions out of schema_migrations", %{dir: dir} do
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")

      assert_raise Ecto.MigrationError, ~r/above 20260103000000/, fn ->
        Migrator.check_version_order!(IntegrationRepo, [dir], [])
      end
    end

    test "counts a version applied without a migration file as applied", %{dir: dir} do
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true)
      File.rm!(migration_path(dir, @profiles, "create_profiles"))

      write_migration!(dir, @orders, "create_orders", "orders")

      assert_raise Ecto.MigrationError, ~r/above 20260103000000/, fn ->
        Migrator.check_version_order!(IntegrationRepo, [dir], [])
      end
    end
  end

  describe "run/3" do
    setup do
      dir = Ecto.Migrator.migrations_path(IntegrationRepo)
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(Path.dirname(dir)) end)
      {:ok, repo_dir: dir}
    end

    test "migrates the directory the repo derives", %{repo_dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")

      assert Migrator.run(IntegrationRepo, :up, all: true) == [@accounts]
      assert applied_versions() == [@accounts]
    end

    test "refuses to migrate a stale version in the directory the repo derives", %{repo_dir: dir} do
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Migrator.run(IntegrationRepo, :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")

      assert_raise Ecto.MigrationError, fn ->
        Migrator.run(IntegrationRepo, :up, all: true)
      end

      assert applied_versions() == [@profiles]
    end
  end

  describe "the behaviour this guards against" do
    test "Ecto.Migrator applies a stale version even with strict_version_order", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true, strict_version_order: true)

      write_migration!(dir, @orders, "create_orders", "orders")
      Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true, strict_version_order: true)

      assert applied_versions() == [@accounts, @orders, @profiles]
      assert table_exists?("orders")
    end

    test "rolling back then reverts a newer migration than the one just deployed", %{dir: dir} do
      write_migration!(dir, @accounts, "create_accounts", "accounts")
      write_migration!(dir, @profiles, "create_profiles", "profiles")
      Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true)

      write_migration!(dir, @orders, "create_orders", "orders")
      assert Ecto.Migrator.run(IntegrationRepo, [dir], :up, all: true) == [@orders]

      assert Ecto.Migrator.run(IntegrationRepo, [dir], :down, step: 1) == [@profiles]
      assert table_exists?("orders")
      refute table_exists?("profiles")
    end
  end

  defp write_migration!(dir, version, name, table) do
    module = "Trogon.Ecto.MigratorIntegrationTest.M#{System.unique_integer([:positive])}"

    File.write!(migration_path(dir, version, name), """
    defmodule #{module} do
      use Ecto.Migration

      def change do
        create table(:#{table}) do
          add(:name, :string)
        end
      end
    end
    """)
  end

  defp migration_path(dir, version, name), do: Path.join(dir, "#{version}_#{name}.exs")

  defp applied_versions do
    %{rows: rows} = IntegrationRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    List.flatten(rows)
  end

  defp table_exists?(table) do
    %{rows: [[exists]]} = IntegrationRepo.query!("SELECT to_regclass($1) IS NOT NULL", ["public.#{table}"])
    exists
  end
end
