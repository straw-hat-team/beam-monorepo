defmodule Trogon.Outbox.PostgresOutbox.OrderingTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  @moduletag partitions: 4

  setup %{prefix: prefix} do
    SQL.query!(TestRepo, ~s|CREATE TABLE "#{prefix}".business (id bigserial PRIMARY KEY, note text)|)
    SQL.query!(TestRepo, ~s|CREATE TABLE "#{prefix}".writer_xids (source text, seq bigint, xid xid8)|)
    :ok
  end

  for strategy <- [:counter, :advisory_lock] do
    @strategy strategy

    test "#{strategy}: a transaction that writes before appending takes an xid below the seq it commits after, " <>
           "and the ordering xid hides the later seq until the earlier one is readable",
         %{prefix: prefix} do
      early = open_transaction()

      early_xid =
        run_in(early, fn ->
          SQL.query!(TestRepo, ~s|INSERT INTO "#{prefix}".business (note) VALUES ('early')|)
          current_xid!()
        end)

      gap_holder = open_transaction()
      gap_xid = run_in(gap_holder, &current_xid!/0)

      {:ok, first} = TestRepo.transaction(fn -> append_recording!(prefix, "source-a", "first", @strategy) end)
      second = run_in(early, fn -> append_recording!(prefix, "source-a", "second", @strategy) end)
      finish(early)

      assert early_xid < gap_xid
      assert gap_xid < writer_xid!(prefix, "source-a", 1)
      assert writer_xid!(prefix, "source-a", 2) == early_xid
      assert first.position.seq.value == 1
      assert second.position.seq.value == 2
      assert second.cursor.xid == first.cursor.xid

      naive = wait_until(fn -> non_empty(naive_readable(prefix, "source-a")) end)

      assert naive == [2]
      assert readable(prefix, "source-a") == []

      finish(gap_holder)

      wait_until(fn -> readable(prefix, "source-a") == [1, 2] end)
    end
  end

  for strategy <- [:counter, :advisory_lock] do
    @strategy strategy

    test "#{strategy}: per-source commit order holds end to end with concurrent writers, random rollbacks, " <>
           "and business writes before appending",
         %{prefix: prefix} do
      start_relay!(prefix, batch_size: 3)

      outcomes =
        1..60
        |> Enum.map(fn n ->
          Task.async(fn ->
            source = "source-#{rem(n, 6)}"

            TestRepo.transaction(fn ->
              if rem(n, 2) == 0 do
                SQL.query!(TestRepo, ~s|INSERT INTO "#{prefix}".business (note) VALUES ($1)|, ["writer-#{n}"])
                Process.sleep(Enum.random(0..10))
              end

              {:ok, events} =
                Trogon.Outbox.append(TestRepo, source, ["writer-#{n}-a", "writer-#{n}-b"],
                  prefix: prefix,
                  strategy: @strategy
                )

              Process.sleep(Enum.random(0..10))
              if rem(n, 5) == 0, do: TestRepo.rollback(:aborted), else: events
            end)
          end)
        end)
        |> Task.await_many(60_000)

      committed = for {:ok, events} <- outcomes, event <- events, do: event
      published = collect_events(length(committed))
      refute_receive {:published, _tag, _batch}, 200

      assert length(committed) == 96
      assert Enum.sort(ids(published)) == Enum.sort(ids(committed))

      for {_source, seqs} <- seqs_by_source(published) do
        assert seqs == Enum.to_list(1..length(seqs))
      end
    end
  end

  defp append_recording!(prefix, source, payload, strategy) do
    {:ok, [event]} = Trogon.Outbox.append(TestRepo, source, payload, prefix: prefix, strategy: strategy)

    SQL.query!(
      TestRepo,
      ~s|INSERT INTO "#{prefix}".writer_xids (source, seq, xid) VALUES ($1, $2, pg_current_xact_id())|,
      [source, event.position.seq.value]
    )

    event
  end

  defp writer_xid!(prefix, source, seq) do
    %Postgrex.Result{rows: [[xid]]} =
      SQL.query!(
        TestRepo,
        ~s(SELECT xid::text::bigint FROM "#{prefix}".writer_xids WHERE source = $1 AND seq = $2),
        [source, seq]
      )

    xid
  end

  defp naive_readable(prefix, source) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT seq FROM "#{prefix}".writer_xids
         WHERE source = $1 AND xid < pg_snapshot_xmin(pg_current_snapshot())
         ORDER BY xid
        """,
        [source]
      )

    List.flatten(rows)
  end

  defp readable(prefix, source) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT seq FROM "#{prefix}".outbox_events
         WHERE source = $1 AND xid < pg_snapshot_xmin(pg_current_snapshot())
         ORDER BY xid, id
        """,
        [source]
      )

    List.flatten(rows)
  end

  defp non_empty([]), do: nil
  defp non_empty(list), do: list
end
