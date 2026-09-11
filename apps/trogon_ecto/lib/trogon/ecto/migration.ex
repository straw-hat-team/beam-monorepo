defmodule Trogon.Ecto.Migration do
  @moduledoc """
  Extends `Ecto.Migration` with column helpers for conventions shared across migrations.

  Import it by using `Trogon.Ecto.Migration` instead of `Ecto.Migration` directly:

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateAccounts do
    use Trogon.Ecto.Migration

    def change do
      create table(:accounts) do
        add_object_id_column(:owner_id, null: false)
        add_currency_code_column()
        add_money_amount_column(:balance)
        add_string_map_column(:labels, null: false)
        add_string_map_column(:annotations)
        add_timestamps()
      end
    end
  end
  ```
  """

  @doc """
  Uses `Ecto.Migration` and imports `Trogon.Ecto.Migration` helpers.

  ## Options

  - `:mode` - one of `:standard`, `:no_transaction`, or `:concurrent`. Defaults to `:standard`.

  ### `:standard`

  Plain `use Ecto.Migration`, running inside the usual DDL transaction.

      use Trogon.Ecto.Migration

  ### `:no_transaction`

  Sets `@disable_ddl_transaction true`. Use it for fast, non-transactional DDL such as
  `ALTER TYPE ... ADD VALUE`, which PostgreSQL refuses to run inside a transaction.

      use Trogon.Ecto.Migration, mode: :no_transaction

  ### `:concurrent`

  Sets `@disable_ddl_transaction true` and `@disable_migration_lock true`. Use it for
  `CREATE INDEX CONCURRENTLY`, which requires both the transaction and the migration lock
  to be disabled.

      use Trogon.Ecto.Migration, mode: :concurrent
  """
  @spec __using__(opts :: Keyword.t()) :: Macro.t()
  defmacro __using__(opts) do
    mode = Keyword.get(opts, :mode, :standard)

    mode_attrs =
      case mode do
        :standard ->
          quote do
          end

        :no_transaction ->
          quote do
            @disable_ddl_transaction true
          end

        :concurrent ->
          quote do
            @disable_ddl_transaction true
            @disable_migration_lock true
          end

        other ->
          raise ArgumentError,
                "unknown :mode #{inspect(other)} for Trogon.Ecto.Migration, " <>
                  "expected one of :standard, :no_transaction, :concurrent"
      end

    quote do
      use Ecto.Migration
      import Trogon.Ecto.Migration

      unquote(mode_attrs)
    end
  end

  @doc """
  Adds a `:timestamptz` column when altering or creating a table.

  Prefer `timestamptz` (timestamp with time zone) over `timestamp` (without time zone),
  since the latter silently discards the time zone information.
  See https://wiki.postgresql.org/wiki/Don't_Do_This#Don.27t_use_timestamp_.28without_time_zone.29
  """
  @spec add_timestamp_column(column :: atom(), opts :: Keyword.t()) :: term()
  def add_timestamp_column(column, opts \\ []) when is_atom(column) do
    Ecto.Migration.add(column, :timestamptz, opts)
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` columns typed as `:timestamptz`.

  Delegates to `Ecto.Migration.timestamps/1`, overriding the default `:type` to
  `:timestamptz`. Caller opts win, so `:inserted_at`, `:updated_at`, and `:type` can
  still be overridden. Column names default to Ecto's own defaults.
  """
  @spec add_timestamps(opts :: Keyword.t()) :: term()
  def add_timestamps(opts \\ []) do
    Ecto.Migration.timestamps(Keyword.put_new(opts, :type, :timestamptz))
  end

  @doc """
  Adds a `:bigint` column for the event-sourcing stream version.

  Defaults to `null: false`; caller opts win.
  """
  @spec add_stream_version_column(opts :: Keyword.t()) :: term()
  def add_stream_version_column(opts \\ []) do
    Ecto.Migration.add(:stream_version, :bigint, Keyword.merge([null: false], opts))
  end

  @doc """
  Adds a `:currency_code` column storing an ISO 4217 alphabetic currency code.
  """
  @spec add_currency_code_column(opts :: Keyword.t()) :: term()
  def add_currency_code_column(opts \\ []) do
    Ecto.Migration.add(:currency_code, :string, opts)
  end

  @doc ~S"""
  Adds a `:"#{name}_amount"` column storing a money amount in minor units (e.g. cents).
  """
  @spec add_money_amount_column(name :: atom(), opts :: Keyword.t()) :: term()
  def add_money_amount_column(name, opts \\ []) when is_atom(name) do
    Ecto.Migration.add(:"#{name}_amount", :integer, opts)
  end

  @doc """
  Adds a `:jsonb` column for a `Trogon.Ecto.StringMap`, `Trogon.Ecto.LabelMap`, or
  `Trogon.Ecto.AnnotationMap` field.

  Defaults to `default: "{}"`; caller opts win. An empty map rather than `NULL`
  keeps a read from having to tell an absent map from one with no entries.

  `:jsonb` rather than Ecto's `:map`, which PostgreSQL renders as whatever
  `config :ecto_sql, :postgres_map_type` says, `"jsonb"` unless an application
  sets it to `"json"`. A map that lands in a `json` column keeps duplicate keys
  and insertion order verbatim, so two writes of the same map are two different
  stored values, and it cannot take the GIN index a lookup by label needs.

  ## Examples

      add_string_map_column(:labels, null: false)
  """
  @spec add_string_map_column(name :: atom(), opts :: Keyword.t()) :: term()
  def add_string_map_column(name, opts \\ []) when is_atom(name) do
    Ecto.Migration.add(name, :jsonb, Keyword.merge([default: "{}"], opts))
  end

  @doc """
  Adds an `:annotations` column, typed as `:jsonb`, for free-form metadata.

  Defaults to `default: "{}"`; caller opts win.
  """
  @deprecated "Use add_string_map_column/2 instead"
  @spec add_annotations_column(opts :: Keyword.t()) :: term()
  def add_annotations_column(opts \\ []) do
    add_string_map_column(:annotations, opts)
  end

  @doc """
  Adds a `:binary_id` column for a raw UUID.

  Use this only for columns storing a raw UUID with no prefix. It stores 16 bytes,
  which keeps indexes small and efficient. Do NOT use it for prefixed ObjectId
  columns; use `add_object_id_column/2` instead.
  """
  @spec add_uuid_column(name :: atom(), opts :: Keyword.t()) :: term()
  def add_uuid_column(name, opts \\ []) when is_atom(name) do
    Ecto.Migration.add(name, :binary_id, opts)
  end

  @doc """
  Adds a `:string` column for a single, known ObjectId type.

  ObjectIds serialize as prefixed strings (e.g. `"user_<uuid>"`), so `:binary_id`
  cannot be used to store them.

  ## Examples

      add_object_id_column(:owner_id, null: false)
  """
  @spec add_object_id_column(name :: atom(), opts :: Keyword.t()) :: term()
  def add_object_id_column(name, opts \\ []) when is_atom(name) do
    Ecto.Migration.add(name, :string, opts)
  end

  @doc """
  Adds a `:string` column for a union of ObjectId types.

  Union ObjectId types must persist the prefix so the stored value can be parsed
  back into the correct concrete type, e.g. `"user_<uuid>"` or `"org_<uuid>"`.
  """
  @spec add_union_object_id_column(name :: atom(), opts :: Keyword.t()) :: term()
  def add_union_object_id_column(name, opts \\ []) when is_atom(name) do
    Ecto.Migration.add(name, :string, opts)
  end
end
