defmodule Trogon.Ecto.Migrator do
  @moduledoc """
  Runs migrations only when their versions are newer than everything already applied.

      defmodule MyApp.Release do
        def migrate do
          for repo <- repos() do
            {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Trogon.Ecto.Migrator.run(&1, :up, all: true))
          end
        end
      end

  Two branches cut from the same commit each generate a migration stamped with the
  time it was generated, so whichever one merges second carries a version older than
  a migration that has already run in production. `Ecto.Migrator` applies it anyway,
  and from then on a rollback reverts the newer migration instead of the one that was
  just deployed, because `Ecto.Migrator.run/4` rolls back in version order rather than
  in the order migrations were applied.

  `Ecto.Migrator` reports this, but only from `Ecto.Migrator.up/4`, and only after
  `do_up/5` has committed both the DDL and the `schema_migrations` row on its own
  connection. Raising there cannot undo the migration, and `Ecto.Migrator.run/4`, which
  `mix ecto.migrate` uses, never reaches that code at all: it goes through `do_direction/5`
  straight to `do_up/5`, so `--strict-version-order` has nothing to act on. Checked
  against `ecto_sql` 3.14.0.

  Refusing to migrate is the only point where the database can still be left untouched,
  so `run/3` compares versions before delegating, and fails the deploy rather than
  leaving a repo whose rollback order no longer matches its deploy order. Recovering
  means giving the offending migration a version above everything applied and deploying
  again.

  Requires `ecto_sql`, which `trogon_ecto` lists as an optional dependency.
  """

  @typedoc """
  A migration and whether it has been applied, as returned by `Ecto.Migrator.migrations/3`.
  """
  @type status :: {:up | :down, version :: integer(), name :: String.t()}

  @doc """
  Checks the version order of the repo's default migrations directory, then runs the
  migrations.

  Drop-in replacement for `Ecto.Migrator.run/3`, taking and returning the same values.
  Only `:up` is checked, since `:down` is expected to visit older versions.
  """
  @spec run(Ecto.Repo.t(), :up | :down, Keyword.t()) :: [integer()]
  def run(repo, direction, opts) do
    run(repo, [Ecto.Migrator.migrations_path(repo)], direction, opts)
  end

  @doc """
  Checks the version order of the given migration sources, then runs the migrations.

  Drop-in replacement for `Ecto.Migrator.run/4`, taking and returning the same values.
  Pass the migration sources here when the repo keeps its migrations somewhere other
  than the directory `Ecto.Migrator.migrations_path/2` derives.
  """
  @spec run(Ecto.Repo.t(), String.t() | [String.t()], :up | :down, Keyword.t()) :: [integer()]
  def run(repo, migration_source, :up, opts) do
    check_version_order!(repo, migration_source, opts)
    Ecto.Migrator.run(repo, migration_source, :up, opts)
  end

  def run(repo, migration_source, direction, opts) do
    Ecto.Migrator.run(repo, migration_source, direction, opts)
  end

  @doc """
  Raises unless every pending migration in the repo's default migrations directory has
  a version above the highest applied one.
  """
  @spec check_version_order!(Ecto.Repo.t(), Keyword.t()) :: :ok
  def check_version_order!(repo, opts \\ []) do
    check_version_order!(repo, [Ecto.Migrator.migrations_path(repo)], opts)
  end

  @doc """
  Raises unless every pending migration in the given migration sources has a version
  above the highest applied one.

  `opts` are forwarded to `Ecto.Migrator.migrations/3`, so the same `:prefix` and
  `:dynamic_repo` that `run/4` migrates are the ones inspected. Reading the applied
  versions creates the `schema_migrations` table when it is missing and takes the
  migration lock, the same as any other migrator call.
  """
  @spec check_version_order!(Ecto.Repo.t(), String.t() | [String.t()], Keyword.t()) :: :ok
  def check_version_order!(repo, migration_source, opts) do
    repo
    |> Ecto.Migrator.migrations(migration_source, opts)
    |> check_statuses!()
  end

  @doc """
  Raises unless every pending migration in `statuses` has a version above the highest
  applied one.

  The database is reached through `Ecto.Migrator.migrations/3` by `check_version_order!/3`,
  which leaves this comparison callable on statuses from anywhere.

  A version applied without a migration file still counts as applied, since deleting the
  file does not put the schema back.
  """
  @spec check_statuses!([status()]) :: :ok
  def check_statuses!(statuses) do
    highest_applied =
      statuses
      |> Stream.filter(&match?({:up, _version, _name}, &1))
      |> Stream.map(fn {_direction, version, _name} -> version end)
      |> Enum.max(&>=/2, fn -> 0 end)

    statuses
    |> Enum.filter(&out_of_order?(&1, highest_applied))
    |> raise_out_of_order!(highest_applied)
  end

  defp out_of_order?({:down, version, _name}, highest_applied), do: version < highest_applied
  defp out_of_order?({:up, _version, _name}, _highest_applied), do: false

  defp raise_out_of_order!([], _highest_applied), do: :ok

  defp raise_out_of_order!(out_of_order, highest_applied) do
    raise Ecto.MigrationError, """
    Refusing to migrate: pending migrations are older than the highest applied version (#{highest_applied}).

    #{Enum.map_join(out_of_order, "\n", fn {_direction, version, name} -> "  #{version} #{name}" end)}

    Applying them would leave this repo rolling back in a different order than it deployed.
    Give each one a version above #{highest_applied} and deploy again.
    """
  end
end
