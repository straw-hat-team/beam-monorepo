defmodule Trogon.Outbox.Migration do
  @moduledoc """
  Versioned migrations for the outbox tables, run from an Ecto migration:

      defmodule MyApp.Repo.Migrations.AddOutbox do
        use Ecto.Migration

        def up, do: Trogon.Outbox.Migration.up(partitions: 64)
        def down, do: Trogon.Outbox.Migration.down()
      end

  ## Options

    * `:prefix` - the schema holding the tables, `"public"` by default. Created when missing.
    * `:partitions` - the fixed partition count, 64 by default. Read only by the first version,
      since changing it in place while a source's unpublished events still sit in its old
      partition lets two relays publish that source out of order. Passing a different count once
      the outbox is already installed raises instead of silently keeping the old one.
    * `:days_ahead` - how many daily event partitions to create ahead of today, 7 by default.
    * `:version` - the version to migrate up to or down to, the latest by default.
  """

  use Ecto.Migration

  alias Trogon.Outbox.{Postgres, PostgresVersion}

  @current_version 2
  @initial_version 0

  @spec up(keyword()) :: :ok
  def up(opts \\ []) do
    repo() |> PostgresVersion.fetch!() |> PostgresVersion.ensure_supported!()

    prefix = Keyword.get(opts, :prefix, "public")
    target = Keyword.get(opts, :version, @current_version)
    current = migrated_version(repo(), prefix: prefix)

    if current > @initial_version, do: validate_partitions!(repo(), prefix, opts)

    if current < target do
      Enum.each((current + 1)..target, fn version -> module(version).up(opts) end)
      record_version(prefix, target)
    end

    :ok
  end

  @spec down(keyword()) :: :ok
  def down(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    target = Keyword.get(opts, :version, @initial_version)
    current = migrated_version(repo(), prefix: prefix)

    if current > target do
      Enum.each(current..(target + 1)//-1, fn version -> module(version).down(opts) end)
      if target > @initial_version, do: record_version(prefix, target)
    end

    :ok
  end

  @doc "The version currently installed under the prefix, 0 when the outbox is not installed."
  @spec migrated_version(Ecto.Repo.t(), keyword()) :: non_neg_integer()
  def migrated_version(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")

    %Postgrex.Result{rows: [[comment]]} =
      Postgres.query!(
        repo,
        "SELECT obj_description(to_regclass($1), 'pg_class')",
        [Postgres.events(prefix)]
      )

    case comment && Integer.parse(comment) do
      {version, ""} -> version
      _not_installed -> @initial_version
    end
  end

  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  defp module(version), do: Module.concat(Trogon.Outbox.Migrations, "V#{version}")

  defp record_version(prefix, version) do
    execute("COMMENT ON TABLE #{Postgres.events(prefix)} IS '#{version}'")
  end

  defp validate_partitions!(repo, prefix, opts) do
    case Keyword.fetch(opts, :partitions) do
      {:ok, partitions} ->
        installed = installed_partitions!(repo, prefix)

        unless partitions == installed do
          raise ArgumentError,
                "the outbox under #{inspect(prefix)} is already installed with #{installed} partitions. " <>
                  "Changing partitions in place is unsafe: drain every relay first, confirming every cursor " <>
                  "reached the end of its partition, then reinstall from a fresh #{inspect(prefix)} schema."
        end

      :error ->
        :ok
    end
  end

  defp installed_partitions!(repo, prefix) do
    %Postgrex.Result{rows: [[count]]} =
      Postgres.query!(repo, "SELECT #{Postgres.name(prefix, "outbox_partition_count")}()", [])

    count
  end
end
