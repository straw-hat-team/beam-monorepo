defmodule Trogon.Ecto.MigratorTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.Migrator

  describe "check_statuses!/1" do
    test "passes when nothing is applied and nothing is pending" do
      assert Migrator.check_statuses!([]) == :ok
    end

    test "passes on a fresh database where every migration is pending" do
      statuses = [
        {:down, 20_260_101_000_000, "create_accounts"},
        {:down, 20_260_102_000_000, "create_profiles"}
      ]

      assert Migrator.check_statuses!(statuses) == :ok
    end

    test "passes when every pending version is above the highest applied one" do
      statuses = [
        {:up, 20_260_101_000_000, "create_accounts"},
        {:up, 20_260_102_000_000, "create_profiles"},
        {:down, 20_260_103_000_000, "create_orders"}
      ]

      assert Migrator.check_statuses!(statuses) == :ok
    end

    test "passes when everything is applied" do
      statuses = [
        {:up, 20_260_101_000_000, "create_accounts"},
        {:up, 20_260_102_000_000, "create_profiles"}
      ]

      assert Migrator.check_statuses!(statuses) == :ok
    end

    test "raises when a pending version is below the highest applied one" do
      statuses = [
        {:down, 20_260_101_000_000, "create_orders"},
        {:up, 20_260_102_000_000, "create_accounts"}
      ]

      assert_raise Ecto.MigrationError, ~r/20260101000000 create_orders/, fn ->
        Migrator.check_statuses!(statuses)
      end
    end

    test "reports the highest applied version as the one to get above" do
      statuses = [
        {:down, 20_260_101_000_000, "create_orders"},
        {:up, 20_260_103_000_000, "create_accounts"}
      ]

      assert_raise Ecto.MigrationError, ~r/above 20260103000000/, fn ->
        Migrator.check_statuses!(statuses)
      end
    end

    test "reports every out of order migration" do
      statuses = [
        {:down, 20_260_101_000_000, "create_orders"},
        {:down, 20_260_102_000_000, "create_invoices"},
        {:up, 20_260_103_000_000, "create_accounts"}
      ]

      error =
        assert_raise Ecto.MigrationError, fn ->
          Migrator.check_statuses!(statuses)
        end

      assert error.message =~ "20260101000000 create_orders"
      assert error.message =~ "20260102000000 create_invoices"
    end

    test "leaves pending versions above the highest applied one out of the failure" do
      statuses = [
        {:down, 20_260_101_000_000, "create_orders"},
        {:up, 20_260_102_000_000, "create_accounts"},
        {:down, 20_260_103_000_000, "create_invoices"}
      ]

      error =
        assert_raise Ecto.MigrationError, fn ->
          Migrator.check_statuses!(statuses)
        end

      assert error.message =~ "20260101000000 create_orders"
      refute error.message =~ "create_invoices"
    end

    test "counts a version applied without a migration file as applied" do
      statuses = [
        {:down, 20_260_101_000_000, "create_orders"},
        {:up, 20_260_102_000_000, "** FILE NOT FOUND **"}
      ]

      assert_raise Ecto.MigrationError, ~r/above 20260102000000/, fn ->
        Migrator.check_statuses!(statuses)
      end
    end
  end
end
