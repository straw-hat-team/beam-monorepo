defmodule Trogon.Outbox.Relay.PoolerGuard do
  @moduledoc """
  Refuses a relay connection that goes through a transaction-mode pooler.

  A relay holds its partitions with a session-level advisory lock, which lives on whichever
  backend process its connection happens to be using. A transaction-mode pooler such as PgBouncer
  hands that connection's statements to any free backend on each new transaction, so the lock can
  end up on a backend the relay no longer talks to, while the relay keeps believing it holds it.
  `Trogon.Outbox.Relay.Store` already catches this once it actually happens during normal
  operation, by comparing `pg_backend_pid()` against the one it captured at startup on every
  lock, read and advance, and stopping the relay on a mismatch; this check exists to catch it
  before that, at startup, without waiting for a reassignment to occur on its own.

  Detection forces the condition instead of waiting for it: a handful of auxiliary connections
  through the same configuration keep the pool busy, while the relay's own connection is queried
  for `pg_backend_pid()` several times. Direct connections and session poolers always answer with
  the same backend; a transaction-mode pooler under that pressure answers with more than one. This
  forcing is also why the check is opt-in rather than automatic: it adds connections of its own
  and takes a moment to run, both at the exact point a relay is trying to start.
  """

  require Logger

  alias Trogon.Outbox.Postgres

  @probe_connections 4
  @probe_rounds 6
  @probe_gap 15
  @probe_hold_seconds 0.03

  @spec ensure_not_pooled!(pid(), keyword()) :: :ok
  def ensure_not_pooled!(conn, connection_opts) do
    case detect(conn, connection_opts) do
      :pooled ->
        raise ArgumentError, """
        the relay's connection goes through a transaction-mode pooler: its backend process \
        changed across statements run on the same connection. A relay's session advisory lock \
        lives on one backend; a transaction-mode pooler can hand the connection's next statement \
        to a different one, so the lock and the relay's view of holding it drift apart. Point \
        the relay's :connection at the database directly, bypassing the pooler.
        """

      :inconclusive ->
        Logger.warning(
          "Trogon.Outbox.Relay could not open auxiliary connections to check whether its own " <>
            "connection goes through a transaction-mode pooler, proceeding unchecked"
        )

        :ok

      :direct ->
        :ok
    end
  end

  defp detect(conn, connection_opts) do
    parent = self()
    ref = make_ref()
    {pid, monitor_ref} = spawn_monitor(fn -> send(parent, {ref, run(conn, connection_opts)}) end)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :inconclusive
    after
      15_000 -> :inconclusive
    end
  end

  defp run(conn, connection_opts) do
    opts =
      connection_opts
      |> Keyword.drop([:connection_listeners, :name, :parameters])
      |> Keyword.merge(pool_size: 1, backoff_type: :stop)

    probe_tasks = for _ <- 1..@probe_connections, do: Task.async(fn -> run_probe(opts) end)
    pids = sample_backend_pid(conn, @probe_rounds)
    results = Enum.map(probe_tasks, &Task.await(&1, 10_000))

    classify(pids, results)
  end

  @doc false
  @spec classify([integer()], [:held | :failed]) :: :pooled | :direct | :inconclusive
  def classify(pids, probe_results) do
    cond do
      Enum.all?(probe_results, &(&1 == :failed)) -> :inconclusive
      length(Enum.uniq(pids)) > 1 -> :pooled
      true -> :direct
    end
  end

  defp run_probe(opts) do
    case Postgrex.start_link(opts) do
      {:ok, probe} ->
        result = if viable?(probe), do: hold(probe), else: :failed
        close_probe(probe)
        result

      {:error, _reason} ->
        :failed
    end
  end

  defp viable?(probe) do
    case Postgrex.query(probe, "SELECT 1", [], timeout: 5_000) do
      {:ok, _result} -> true
      {:error, _reason} -> false
    end
  catch
    :exit, _reason -> false
  end

  defp hold(probe) do
    for _ <- 1..@probe_rounds, do: Postgrex.query(probe, "SELECT pg_sleep($1)", [@probe_hold_seconds])
    :held
  end

  defp sample_backend_pid(conn, rounds) do
    for round <- 1..rounds do
      if round > 1, do: Process.sleep(@probe_gap)
      query_backend_pid!(conn)
    end
  end

  # A reassignment under a transaction-mode pooler can land mid-statement, surfacing as the
  # backend closing the connection instead of the next statement quietly picking up a different
  # one. Retrying immediately gives the pooler a chance to hand the connection a live backend
  # before treating the round as unreadable.
  defp query_backend_pid!(conn, attempts_left \\ 3) do
    %Postgrex.Result{rows: [[pid]]} = Postgres.query!(conn, "SELECT pg_backend_pid()", [])
    pid
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      if attempts_left > 1, do: query_backend_pid!(conn, attempts_left - 1), else: reraise(error, __STACKTRACE__)
  end

  defp close_probe(probe) do
    Postgrex.query(probe, "ROLLBACK", [])
    GenServer.stop(probe, :normal, 1_000)
  catch
    :exit, _reason -> :ok
  end
end
