defmodule Trogon.Outbox.TestSupport.OutboxCase do
  @moduledoc """
  Installs the outbox under a fresh schema for every test, with helpers to append, run relays,
  and collect what they publish.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.{Batch, Event, Relay}
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.{OutboxMigration, TestPublisher}

  using do
    quote do
      import Trogon.Outbox.TestSupport.OutboxCase

      alias Ecto.Adapters.SQL
      alias Trogon.Outbox.TestRepo
    end
  end

  setup context do
    prefix = "outbox_t#{System.unique_integer([:positive])}"
    install!(prefix, Map.get(context, :partitions, 8))
    on_exit(fn -> SQL.query!(TestRepo, ~s(DROP SCHEMA IF EXISTS "#{prefix}" CASCADE)) end)
    {:ok, prefix: prefix}
  end

  def install!(prefix, partitions) do
    SQL.query!(TestRepo, ~s(CREATE SCHEMA IF NOT EXISTS "#{prefix}"))
    OutboxMigration.put_partitions(prefix, partitions)
    Ecto.Migrator.run(TestRepo, [{1, OutboxMigration}], :up, all: true, prefix: prefix, log: false)
  end

  def append!(prefix, source, payloads, opts \\ []) do
    {:ok, events} =
      TestRepo.transaction(fn ->
        {:ok, events} = Trogon.Outbox.append(TestRepo, source, payloads, [prefix: prefix] ++ opts)
        events
      end)

    events
  end

  def start_relay!(prefix, opts \\ []) do
    test_pid = self()
    relay = Keyword.get(opts, :relay, "test")
    publisher_opts = Keyword.take(opts, [:handler]) ++ [test_pid: test_pid, tag: Keyword.get(opts, :tag, relay)]

    relay_opts =
      [
        repo: TestRepo,
        prefix: prefix,
        relay: relay,
        publisher: {TestPublisher, publisher_opts},
        min_poll_interval: 5,
        max_poll_interval: 50,
        lock_interval: 50
      ]
      |> Keyword.merge(Keyword.drop(opts, [:handler, :tag, :restart, :id]))

    child = %{
      id: Keyword.get(opts, :id, make_ref()),
      start: {Relay, :start_link, [relay_opts]},
      restart: Keyword.get(opts, :restart, :permanent)
    }

    ExUnit.Callbacks.start_supervised!(child)
  end

  @doc "Receives published batches until `count` events arrived, returning them in publish order."
  def collect_events(count, timeout \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    collect_events(count, deadline, [])
  end

  defp collect_events(count, _deadline, events) when length(events) >= count, do: events

  defp collect_events(count, deadline, events) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:published, _tag, %Batch{events: batch}} -> collect_events(count, deadline, events ++ batch)
    after
      remaining ->
        ExUnit.Assertions.flunk("expected #{count} published events, got #{length(events)}: #{inspect(ids(events))}")
    end
  end

  def ids(events), do: Enum.map(events, &to_string(Event.message_id(&1)))

  def seqs_by_source(events) do
    events
    |> Enum.group_by(& &1.position.source.value, & &1.position.seq.value)
  end

  def cursor_row(prefix, relay, partition) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        ~s(SELECT xid::text::bigint, id FROM "#{prefix}".outbox_cursors WHERE relay = $1 AND partition = $2),
        [relay, partition]
      )

    case rows do
      [[xid, id]] -> {xid, id}
      [] -> nil
    end
  end

  def wait_until(fun, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    cond do
      result = fun.() ->
        result

      System.monotonic_time(:millisecond) > deadline ->
        ExUnit.Assertions.flunk("the condition never became true")

      true ->
        Process.sleep(20)
        do_wait_until(fun, deadline)
    end
  end

  @doc "Opens a transaction in its own process, kept open until `finish/2`."
  def open_transaction do
    Task.async(fn -> TestRepo.transaction(&transaction_loop/0) end)
  end

  defp transaction_loop do
    receive do
      {:run, fun, from, ref} ->
        send(from, {ref, fun.()})
        transaction_loop()

      :commit ->
        :committed

      :rollback ->
        TestRepo.rollback(:rolled_back)
    after
      30_000 -> raise "the open transaction was never finished"
    end
  end

  @doc "Runs `fun` inside the open transaction and returns its result."
  def run_in(transaction, fun) do
    ref = make_ref()
    send(transaction.pid, {:run, fun, self(), ref})

    receive do
      {^ref, result} -> result
    after
      10_000 -> ExUnit.Assertions.flunk("the open transaction did not run the step in time")
    end
  end

  def finish(transaction, how \\ :commit) do
    send(transaction.pid, how)
    Task.await(transaction, 10_000)
  end

  def current_xid! do
    %Postgrex.Result{rows: [[xid]]} = SQL.query!(TestRepo, "SELECT pg_current_xact_id()::text::bigint")
    xid
  end
end
