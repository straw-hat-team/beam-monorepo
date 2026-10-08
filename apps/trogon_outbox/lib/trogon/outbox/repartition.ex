defmodule Trogon.Outbox.Repartition do
  @moduledoc """
  Changes the partition count of an installed outbox, the one case `Trogon.Outbox.Migration.up/1`
  refuses in place.

  `outbox_partition/1` is `IMMUTABLE`, so a plan calling it can be inlined at plan time, but
  `change!/3` replaces it with `CREATE OR REPLACE FUNCTION`, which keeps its OID and invalidates
  every cached plan depending on it. The next `append/4` on any connection replans against the new
  definition, so there is no window where a connection keeps using the old count after `change!/3`
  commits.

  The remaining risk is a source whose unpublished events still sit under the old partition
  numbering: a relay reading partition 3 under the old count and partition 5 under the new one
  could publish the same source out of order across the two. `change!/3` refuses to run while any
  such event exists, the same check `Trogon.Outbox.Retention` uses to decide whether a day is safe
  to drop, run across every partition instead of one day.

  That check alone leaves a gap between confirming no event is unpublished and replacing the
  functions, during which a new append could land under the old count. `change!/3` closes it by
  taking an `ACCESS EXCLUSIVE` lock on `outbox_sources` first: every `append/4` starts by writing
  to that table, so the lock blocks every new one and waits for one already running to finish,
  before the functions are replaced in the same transaction. Nothing can append under the old
  count after the precondition passes, and nothing appends under a half-changed one. Every event a
  source has before the swap is published before it has any event after the swap, so per-source
  order survives even though its partition number can change.

  What this does not do: pick up the new partitions for a relay that is already running. A relay's
  partition set is read once at start, so every relay needs restarting after `change!/3` commits
  to cover the full new range; one left running keeps serving only the partitions it already held.

  ## Options

    * `:prefix` - the schema holding the outbox tables, `"public"` by default.
    * `:lock_timeout` - in milliseconds, 5000 by default. Long enough for an ordinary append to
      finish, short enough to fail loudly instead of queuing behind a stuck one.
  """

  alias Trogon.Outbox.Postgres

  @min_partitions 1
  @max_partitions 32_767

  @spec change!(Ecto.Repo.t(), pos_integer(), keyword()) :: :ok
  def change!(repo, partitions, opts \\ []) do
    unless is_integer(partitions) and partitions >= @min_partitions and partitions <= @max_partitions do
      raise ArgumentError,
            "partitions must be an integer between #{@min_partitions} and #{@max_partitions}, got: #{inspect(partitions)}"
    end

    prefix = Postgres.validate_prefix!(Keyword.get(opts, :prefix, "public"))
    lock_timeout = Keyword.get(opts, :lock_timeout, 5_000)

    ensure_drained!(repo, prefix)
    run(repo, prefix, partitions, lock_timeout)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :lock_not_available do
        raise RuntimeError,
              "could not take the outbox_sources lock before lock_timeout elapsed; a writer is still in flight. Retry."
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp run(repo, prefix, partitions, lock_timeout) do
    result =
      repo.transaction(fn ->
        Postgres.query!(repo, "SET LOCAL lock_timeout = #{Integer.to_string(lock_timeout)}", [])
        Postgres.query!(repo, "LOCK TABLE #{Postgres.sources(prefix)} IN ACCESS EXCLUSIVE MODE", [])

        if unpublished?(repo, prefix) do
          repo.rollback(:unpublished)
        else
          replace_functions!(repo, prefix, partitions)
        end
      end)

    case result do
      {:ok, :ok} ->
        :ok

      {:error, :unpublished} ->
        raise ArgumentError,
              "the outbox under #{inspect(prefix)} gained an unpublished event while change!/3 waited " <>
                "for the lock. Drain every relay again and retry."
    end
  end

  defp ensure_drained!(repo, prefix) do
    if unpublished?(repo, prefix) do
      raise ArgumentError,
            "the outbox under #{inspect(prefix)} still has unpublished events. Drain every relay first, " <>
              "confirming every cursor reached the end of its partition, then retry."
    end
  end

  defp unpublished?(repo, prefix) do
    %Postgrex.Result{rows: [[unpublished]]} =
      Postgres.query!(
        repo,
        """
        SELECT EXISTS (
          SELECT 1 FROM #{Postgres.events(prefix)} e
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

  defp replace_functions!(repo, prefix, partitions) do
    Postgres.query!(
      repo,
      """
      CREATE OR REPLACE FUNCTION #{Postgres.name(prefix, "outbox_partition_count")}() RETURNS integer
      LANGUAGE sql IMMUTABLE PARALLEL SAFE
      AS $$ SELECT #{partitions} $$
      """,
      []
    )

    Postgres.query!(
      repo,
      """
      CREATE OR REPLACE FUNCTION #{Postgres.name(prefix, "outbox_partition")}(source text) RETURNS integer
      LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
      AS $$ SELECT (((hashtextextended(source, 0) % #{partitions}) + #{partitions}) % #{partitions})::integer $$
      """,
      []
    )

    :ok
  end
end
