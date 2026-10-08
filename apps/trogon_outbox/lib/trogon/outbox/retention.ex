defmodule Trogon.Outbox.Retention do
  @moduledoc """
  Daily event partitions: create them ahead of time and drop old ones whole.

  Dropping a partition removes its file, so retention leaves no dead tuples behind. A day is only
  dropped once every relay cursor has passed all of its events. If a transaction is still writing
  to that day's partition when the drop starts, the detach waits for it instead of dropping out
  from under it, and the unpublished check that runs again right after the detach catches anything
  that transaction wrote before the drop happens.

  Schedule `create_partitions/2` and `drop_partitions/2` daily. An insert for a day without a
  partition fails, so keep `:days_ahead` well above the scheduling interval.
  """

  alias Trogon.Outbox.Postgres

  @type kept_reason :: :unpublished | :locked
  @type result :: %{dropped: [Date.t()], kept: [{Date.t(), kept_reason()}]}

  @doc """
  Creates the daily partitions from `:today` through `:days_ahead` days later.

  Options are `:prefix`, `:days_ahead` (7 by default), and `:today` (UTC today by default).
  """
  @spec create_partitions(Ecto.Repo.t(), keyword()) :: :ok
  def create_partitions(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")
    today = Keyword.get(opts, :today, Date.utc_today())
    days_ahead = Keyword.get(opts, :days_ahead, 7)

    today
    |> Date.range(Date.add(today, days_ahead))
    |> Enum.each(&Postgres.query!(repo, create_partition_sql(prefix, &1), []))
  end

  @doc """
  Drops the daily partitions that end on or before `:before`.

  Options are `:prefix`, `:before` (required), and `:lock_timeout` in milliseconds (100 by
  default). A day with unpublished events is kept without even attempting a detach. Otherwise the
  partition is detached with `DETACH PARTITION ... CONCURRENTLY`, which keeps appends to every
  other partition flowing and only waits, without blocking anything else, for a transaction already
  writing to this one to finish; a lock not granted within `:lock_timeout` keeps the day instead of
  waiting, retried on the next run, so a slow writer never queues behind the drop. If that wait for
  an already-granted lock outlasts `:lock_timeout` while still mid-detach, the partition is left
  detached but not yet dropped; the next run finds it in that state and finishes it with `DETACH
  PARTITION ... FINALIZE` before dropping it.

  The unpublished check runs again right after the detach, before the drop. A transaction starting
  after the detach already began can still legally write to today's own day until it is actually
  gone, since the detach only waits for writers already in progress, it does not block a new one.
  The second check catches what such a writer left behind and attaches the partition back instead
  of dropping it, rather than relying on ruling out that writer ahead of time.
  """
  @spec drop_partitions(Ecto.Repo.t(), keyword()) :: {:ok, result()}
  def drop_partitions(repo, opts) do
    prefix = Keyword.get(opts, :prefix, "public")
    before = Keyword.fetch!(opts, :before)
    lock_timeout = Keyword.get(opts, :lock_timeout, 100)

    result =
      repo
      |> partitions(prefix: prefix)
      |> Enum.filter(&(Date.compare(Date.add(&1, 1), before) != :gt))
      |> Enum.reduce(%{dropped: [], kept: []}, fn day, acc ->
        case drop_partition(repo, prefix, day, lock_timeout) do
          :dropped -> %{acc | dropped: [day | acc.dropped]}
          {:kept, reason} -> %{acc | kept: [{day, reason} | acc.kept]}
        end
      end)

    {:ok, %{dropped: Enum.reverse(result.dropped), kept: Enum.reverse(result.kept)}}
  end

  @doc "The days that currently have an event partition, oldest first."
  @spec partitions(Ecto.Repo.t(), keyword()) :: [Date.t()]
  def partitions(repo, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "public")

    %Postgrex.Result{rows: rows} =
      Postgres.query!(
        repo,
        """
        SELECT child.relname
          FROM pg_inherits
          JOIN pg_class child ON child.oid = pg_inherits.inhrelid
         WHERE pg_inherits.inhparent = to_regclass($1)
        """,
        [Postgres.events(prefix)]
      )

    rows
    |> Enum.flat_map(fn [name] -> parse_day(name) end)
    |> Enum.sort(Date)
  end

  @doc false
  @spec create_partition_sql(String.t(), Date.t()) :: String.t()
  def create_partition_sql(prefix, %Date{} = day) do
    """
    CREATE TABLE IF NOT EXISTS #{partition_name(prefix, day)}
    PARTITION OF #{Postgres.events(prefix)}
    FOR VALUES FROM ('#{Date.to_iso8601(day)} 00:00:00+00') TO ('#{Date.to_iso8601(Date.add(day, 1))} 00:00:00+00')
    """
  end

  # A detach left pending by an earlier lock timeout hides the partition from the relay, so events
  # committed into it late can never publish until the detach is finalized and the day reattached.
  defp drop_partition(repo, prefix, day, lock_timeout) do
    if not detach_pending?(repo, prefix, day) and unpublished?(repo, prefix, day) do
      {:kept, :unpublished}
    else
      drop!(repo, prefix, day, lock_timeout)
    end
  end

  defp detach_pending?(repo, prefix, day) do
    %Postgrex.Result{rows: rows} =
      Postgres.query!(
        repo,
        "SELECT inhdetachpending FROM pg_inherits WHERE inhrelid = to_regclass($1)",
        [partition_name(prefix, day)]
      )

    rows == [[true]]
  end

  defp unpublished?(repo, prefix, day) do
    %Postgrex.Result{rows: [[unpublished]]} =
      Postgres.query!(
        repo,
        """
        SELECT EXISTS (
          SELECT 1 FROM #{partition_name(prefix, day)} e
           WHERE NOT EXISTS (SELECT 1 FROM #{Postgres.cursors(prefix)} c WHERE c.partition = e.partition)
              OR EXISTS (
                SELECT 1 FROM #{Postgres.cursors(prefix)} c
                 WHERE c.partition = e.partition AND (c.xid, c.id) < (e.xid, e.id)
              )
        )
        """,
        []
      )

    unpublished
  end

  defp drop!(repo, prefix, day, lock_timeout) do
    partition = partition_name(prefix, day)
    events = Postgres.events(prefix)

    repo.checkout(fn ->
      Postgres.query!(repo, "SET lock_timeout = #{Integer.to_string(lock_timeout)}", [])

      try do
        detach!(repo, events, partition)
      after
        Postgres.query!(repo, "RESET lock_timeout", [])
      end

      if unpublished?(repo, prefix, day) do
        attach!(repo, events, partition, day)
        {:kept, :unpublished}
      else
        Postgres.query!(repo, "DROP TABLE #{partition}", [])
        :dropped
      end
    end)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :lock_not_available, do: {:kept, :locked}, else: reraise(error, __STACKTRACE__)
  end

  defp detach!(repo, events, partition) do
    Postgres.query!(repo, "ALTER TABLE #{events} DETACH PARTITION #{partition} CONCURRENTLY", [])
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :object_not_in_prerequisite_state do
        finalize!(repo, events, partition)
      else
        reraise(error, __STACKTRACE__)
      end
  end

  # FINALIZE completes a detach left pending by an earlier run that timed out mid-wait. If nothing
  # is pending by the time this runs, the detach already went through on its own in the meantime;
  # that is success too, not an error to surface.
  defp finalize!(repo, events, partition) do
    Postgres.query!(repo, "ALTER TABLE #{events} DETACH PARTITION #{partition} FINALIZE", [])
  rescue
    error in Postgrex.Error ->
      unless error.postgres[:code] == :object_not_in_prerequisite_state, do: reraise(error, __STACKTRACE__)
  end

  defp attach!(repo, events, partition, day) do
    Postgres.query!(
      repo,
      """
      ALTER TABLE #{events} ATTACH PARTITION #{partition}
      FOR VALUES FROM ('#{Date.to_iso8601(day)} 00:00:00+00') TO ('#{Date.to_iso8601(Date.add(day, 1))} 00:00:00+00')
      """,
      []
    )
  end

  defp partition_name(prefix, day), do: Postgres.name(prefix, "outbox_events_" <> Calendar.strftime(day, "%Y%m%d"))

  defp parse_day("outbox_events_" <> <<year::binary-4, month::binary-2, day::binary-2>>) do
    case Date.from_iso8601("#{year}-#{month}-#{day}") do
      {:ok, date} -> [date]
      {:error, _reason} -> []
    end
  end

  defp parse_day(_name), do: []
end
