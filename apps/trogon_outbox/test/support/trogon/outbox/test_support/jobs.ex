defmodule Trogon.Outbox.TestSupport.Jobs do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  @spec truncate!() :: :ok
  def truncate! do
    SQL.query!(TestRepo, "TRUNCATE TABLE outbox_jobs RESTART IDENTITY")
    :ok
  end

  @spec insert!(String.t(), String.t()) :: pos_integer()
  def insert!(source, state) do
    %Postgrex.Result{rows: [[id]]} =
      SQL.query!(
        TestRepo,
        "INSERT INTO outbox_jobs (source, state) VALUES ($1, $2) RETURNING id",
        [source, state]
      )

    id
  end

  @spec mark_completed!(pos_integer()) :: :ok
  def mark_completed!(id) do
    SQL.query!(TestRepo, "UPDATE outbox_jobs SET state = 'completed' WHERE id = $1", [id])
    :ok
  end

  @spec created_at!(pos_integer()) :: NaiveDateTime.t()
  def created_at!(id) do
    %Postgrex.Result{rows: [[created_at]]} =
      SQL.query!(TestRepo, "SELECT created_at FROM outbox_jobs WHERE id = $1", [id])

    created_at
  end

  @spec rows_with_created_at_after(NaiveDateTime.t()) :: list(pos_integer())
  def rows_with_created_at_after(cursor) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        "SELECT id FROM outbox_jobs WHERE created_at > $1 ORDER BY created_at",
        [cursor]
      )

    Enum.map(rows, fn [id] -> id end)
  end

  @spec lock_source!(String.t()) :: :ok
  def lock_source!(source) do
    SQL.query!(TestRepo, "SELECT pg_advisory_xact_lock(hashtext($1))", [source])
    :ok
  end
end
