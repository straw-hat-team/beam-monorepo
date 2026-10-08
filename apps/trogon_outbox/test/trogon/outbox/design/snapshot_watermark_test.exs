defmodule Trogon.Outbox.Design.SnapshotWatermarkTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  @table "design_watermark_events"

  setup do
    SQL.query!(TestRepo, "DROP TABLE IF EXISTS #{@table}")

    SQL.query!(TestRepo, """
    CREATE TABLE #{@table} (
      id bigserial PRIMARY KEY,
      xid xid8 NOT NULL DEFAULT pg_current_xact_id(),
      payload text
    )
    """)

    on_exit(fn -> SQL.query!(TestRepo, "DROP TABLE IF EXISTS #{@table}") end)
    :ok
  end

  test "an id > last_id cursor skips a row whose transaction took its id first but committed last" do
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          {id, _xid} = insert_event!("a")
          send(test_pid, {:inserted, id})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the held transaction did not receive the release signal")
          end

          id
        end)
      end)

    id_a =
      receive do
        {:inserted, id} -> id
      after
        5_000 -> flunk("the held transaction did not insert in time")
      end

    {id_b, _xid} = insert_event!("b")

    first_batch = read_after_id(0)
    last_id = List.last(first_batch)

    send(held_transaction.pid, :release)
    {:ok, ^id_a} = Task.await(held_transaction, 5_000)

    second_batch = read_after_id(last_id)

    assert id_a < id_b
    assert first_batch == [id_b]
    assert second_batch == []
    assert id_a not in (first_batch ++ second_batch)
  end

  test "a snapshot watermark cursor reads a row whose transaction took its id first but committed last" do
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          {id, xid} = insert_event!("a")
          send(test_pid, {:inserted, id, xid})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the held transaction did not receive the release signal")
          end

          id
        end)
      end)

    {id_a, xid_a} =
      receive do
        {:inserted, id, xid} -> {id, xid}
      after
        5_000 -> flunk("the held transaction did not insert in time")
      end

    {id_b, xid_b} = insert_event!("b")

    {first_batch, cursor} = read_below_watermark(0)

    send(held_transaction.pid, :release)
    {:ok, ^id_a} = Task.await(held_transaction, 5_000)

    {second_batch, _cursor} = read_below_watermark_until(cursor, xid_b)

    assert id_a < id_b
    assert xid_a < xid_b
    assert cursor <= xid_a
    assert first_batch == []
    assert second_batch == [id_a, id_b]
  end

  test "a long-open transaction with an assigned xid holds pg_snapshot_xmin back even after later transactions commit" do
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          %Postgrex.Result{rows: [[xid]]} = SQL.query!(TestRepo, "SELECT pg_current_xact_id()::text::bigint")
          send(test_pid, {:xid_assigned, xid})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the held transaction did not receive the release signal")
          end
        end)
      end)

    held_xid =
      receive do
        {:xid_assigned, xid} -> xid
      after
        5_000 -> flunk("the held transaction did not take an xid in time")
      end

    committed = Enum.map(1..3, fn n -> insert_event!("later-#{n}") end)
    {committed_ids, committed_xids} = Enum.unzip(committed)

    watermark_while_open = watermark!()
    {batch_while_open, cursor} = read_below_watermark(0)

    send(held_transaction.pid, :release)
    {:ok, :ok} = Task.await(held_transaction, 5_000)

    {batch_after_close, _cursor} = read_below_watermark_until(cursor, Enum.max(committed_xids))

    assert Enum.all?(committed_xids, &(&1 > held_xid))
    assert watermark_while_open <= held_xid
    assert batch_while_open == []
    assert batch_after_close == committed_ids
  end

  test "a long-open read-only transaction without an assigned xid does not hold pg_snapshot_xmin back" do
    test_pid = self()

    held_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          SQL.query!(TestRepo, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
          SQL.query!(TestRepo, "SELECT count(*) FROM #{@table}")
          %Postgrex.Result{rows: [[pid]]} = SQL.query!(TestRepo, "SELECT pg_backend_pid()")
          send(test_pid, {:snapshot_taken, pid})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the held transaction did not receive the release signal")
          end
        end)
      end)

    held_pid =
      receive do
        {:snapshot_taken, pid} -> pid
      after
        5_000 -> flunk("the held transaction did not take a snapshot in time")
      end

    {id, xid} = insert_event!("after-snapshot")
    {batch, _cursor} = read_below_watermark_until(0, xid)

    %Postgrex.Result{rows: [[backend_xid, backend_xmin]]} =
      SQL.query!(
        TestRepo,
        "SELECT backend_xid::text, backend_xmin::text FROM pg_stat_activity WHERE pid = $1",
        [held_pid]
      )

    send(held_transaction.pid, :release)
    {:ok, :ok} = Task.await(held_transaction, 5_000)

    assert backend_xid == nil
    assert backend_xmin != nil
    assert batch == [id]
  end

  test "an open transaction in another database of the same cluster holds pg_snapshot_xmin back" do
    test_pid = self()
    other_database_config = Keyword.put(TestRepo.config(), :database, "postgres")

    held_transaction =
      Task.async(fn ->
        {:ok, conn} = Postgrex.start_link(other_database_config)

        Postgrex.transaction(conn, fn conn ->
          %Postgrex.Result{rows: [[xid]]} = Postgrex.query!(conn, "SELECT pg_current_xact_id()::text::bigint", [])
          send(test_pid, {:xid_assigned, xid})

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the other database transaction did not receive the release signal")
          end
        end)
      end)

    held_xid =
      receive do
        {:xid_assigned, xid} -> xid
      after
        5_000 -> flunk("the other database transaction did not take an xid in time")
      end

    {id, xid} = insert_event!("this-database")
    watermark_while_open = watermark!()
    {batch_while_open, cursor} = read_below_watermark(0)

    send(held_transaction.pid, :release)
    {:ok, :ok} = Task.await(held_transaction, 5_000)

    {batch_after_close, _cursor} = read_below_watermark_until(cursor, xid)

    assert xid > held_xid
    assert watermark_while_open <= held_xid
    assert batch_while_open == []
    assert batch_after_close == [id]
  end

  defp insert_event!(payload) do
    %Postgrex.Result{rows: [[id, xid]]} =
      SQL.query!(
        TestRepo,
        "INSERT INTO #{@table} (payload) VALUES ($1) RETURNING id, xid::text::bigint",
        [payload]
      )

    {id, xid}
  end

  defp read_after_id(last_id) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(TestRepo, "SELECT id FROM #{@table} WHERE id > $1 ORDER BY id", [last_id])

    Enum.map(rows, fn [id] -> id end)
  end

  defp watermark! do
    %Postgrex.Result{rows: [[watermark]]} =
      SQL.query!(TestRepo, "SELECT pg_snapshot_xmin(pg_current_snapshot())::text::bigint")

    watermark
  end

  defp read_below_watermark(cursor) do
    watermark = watermark!()

    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT id FROM #{@table}
         WHERE xid >= $1::bigint::text::xid8
           AND xid < $2::bigint::text::xid8
         ORDER BY xid, id
        """,
        [cursor, watermark]
      )

    {Enum.map(rows, fn [id] -> id end), watermark}
  end

  # Other databases on the same cluster can hold the watermark back briefly, so wait for it to pass.
  defp read_below_watermark_until(cursor, xid, attempts \\ 100) do
    {batch, watermark} = read_below_watermark(cursor)

    cond do
      watermark > xid ->
        {batch, watermark}

      attempts == 0 ->
        flunk("the snapshot watermark #{watermark} never advanced past xid #{xid}")

      true ->
        Process.sleep(50)
        read_below_watermark_until(cursor, xid, attempts - 1)
    end
  end
end
