defmodule Trogon.Outbox.Design.PerSourceCounterTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  @streams "design_counter_streams"
  @events "design_counter_events"

  setup do
    drop_tables!()

    SQL.query!(TestRepo, "CREATE TABLE #{@streams} (source text PRIMARY KEY, version bigint NOT NULL DEFAULT 0)")

    SQL.query!(TestRepo, """
    CREATE TABLE #{@events} (
      id bigserial PRIMARY KEY,
      source text NOT NULL,
      seq bigint NOT NULL,
      payload text,
      UNIQUE (source, seq)
    )
    """)

    SQL.query!(TestRepo, "INSERT INTO #{@streams} (source) VALUES ('source-a'), ('source-b')")

    on_exit(&drop_tables!/0)
    :ok
  end

  test "a rolled-back writer leaves no gap and seq follows commit order within a source" do
    test_pid = self()

    rolled_back =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          seq = append!("source-a", "rolled-back")
          send(test_pid, {:appended, :rolled_back, seq})

          receive do
            :release -> TestRepo.rollback(:aborted)
          after
            5_000 -> flunk("the rolled-back writer did not receive the release signal")
          end
        end)
      end)

    assert_receive {:appended, :rolled_back, 1}, 5_000

    first = held_writer("source-a", :first)
    assert Task.yield(first, 300) == nil

    send(rolled_back.pid, :release)
    assert {:error, :aborted} = Task.await(rolled_back, 5_000)

    assert_receive {:appended, :first, seq_first}, 5_000

    second = held_writer("source-a", :second)
    assert Task.yield(second, 300) == nil

    send(first.pid, :release)
    assert {:ok, ^seq_first} = Task.await(first, 5_000)

    assert_receive {:appended, :second, seq_second}, 5_000
    send(second.pid, :release)
    assert {:ok, ^seq_second} = Task.await(second, 5_000)

    {:ok, seq_third} = TestRepo.transaction(fn -> append!("source-a", "third") end)

    assert [seq_first, seq_second, seq_third] == [1, 2, 3]
    assert committed_seqs("source-a") == [{1, "first"}, {2, "second"}, {3, "third"}]
  end

  test "concurrent writers with random rollbacks on one source commit a contiguous seq from 1" do
    outcomes =
      1..8
      |> Enum.map(fn n ->
        Task.async(fn ->
          TestRepo.transaction(fn ->
            seq = append!("source-a", "writer-#{n}")
            Process.sleep(Enum.random(0..20))
            if rem(n, 3) == 0, do: TestRepo.rollback(:aborted), else: seq
          end)
        end)
      end)
      |> Task.await_many(10_000)

    committed = for {:ok, seq} <- outcomes, do: seq
    seqs = Enum.map(committed_seqs("source-a"), fn {seq, _payload} -> seq end)

    assert length(committed) == 6
    assert Enum.sort(committed) == Enum.to_list(1..6)
    assert seqs == Enum.to_list(1..6)
  end

  test "a writer on source B is not blocked by an open transaction on source A" do
    holder = held_writer("source-a", :holder)
    assert_receive {:appended, :holder, 1}, 5_000

    other_source =
      Task.async(fn ->
        TestRepo.transaction(fn -> append!("source-b", "unrelated") end)
      end)

    assert Task.await(other_source, 1_000) == {:ok, 1}

    send(holder.pid, :release)
    assert {:ok, 1} = Task.await(holder, 5_000)
  end

  test "a second writer on source A waits on the first writer's row lock and proceeds only after it commits" do
    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          seq = append!("source-a", "holder")
          send(test_pid, {:appended, :holder, seq, backend_pid!()})

          receive do
            :release -> seq
          after
            5_000 -> flunk("the holder did not receive the release signal")
          end
        end)
      end)

    holder_pid =
      receive do
        {:appended, :holder, 1, pid} -> pid
      after
        5_000 -> flunk("the holder did not append in time")
      end

    waiter =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          send(test_pid, {:waiter_pid, backend_pid!()})
          append!("source-a", "waiter")
        end)
      end)

    waiter_pid =
      receive do
        {:waiter_pid, pid} -> pid
      after
        5_000 -> flunk("the waiter did not start in time")
      end

    assert blocking_pids_until(waiter_pid, holder_pid) == [holder_pid]
    assert Task.yield(waiter, 300) == nil

    send(holder.pid, :release)

    assert {:ok, 1} = Task.await(holder, 5_000)
    assert {:ok, 2} = Task.await(waiter, 5_000)
  end

  defp drop_tables! do
    SQL.query!(TestRepo, "DROP TABLE IF EXISTS #{@events}")
    SQL.query!(TestRepo, "DROP TABLE IF EXISTS #{@streams}")
  end

  defp append!(source, payload) do
    %Postgrex.Result{rows: [[seq]]} =
      SQL.query!(TestRepo, "UPDATE #{@streams} SET version = version + 1 WHERE source = $1 RETURNING version", [source])

    SQL.query!(TestRepo, "INSERT INTO #{@events} (source, seq, payload) VALUES ($1, $2, $3)", [source, seq, payload])
    seq
  end

  defp held_writer(source, name) do
    test_pid = self()

    Task.async(fn ->
      TestRepo.transaction(fn ->
        seq = append!(source, Atom.to_string(name))
        send(test_pid, {:appended, name, seq})

        receive do
          :release -> seq
        after
          5_000 -> flunk("the #{name} writer did not receive the release signal")
        end
      end)
    end)
  end

  defp committed_seqs(source) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(TestRepo, "SELECT seq, payload FROM #{@events} WHERE source = $1 ORDER BY seq", [source])

    Enum.map(rows, fn [seq, payload] -> {seq, payload} end)
  end

  defp backend_pid! do
    %Postgrex.Result{rows: [[pid]]} = SQL.query!(TestRepo, "SELECT pg_backend_pid()")
    pid
  end

  defp blocking_pids_until(waiter_pid, expected, attempts \\ 100) do
    %Postgrex.Result{rows: [[pids]]} = SQL.query!(TestRepo, "SELECT pg_blocking_pids($1)", [waiter_pid])

    cond do
      pids == [expected] ->
        pids

      attempts == 0 ->
        flunk("the waiter was never blocked by the holder, blocking pids: #{inspect(pids)}")

      true ->
        Process.sleep(20)
        blocking_pids_until(waiter_pid, expected, attempts - 1)
    end
  end
end
