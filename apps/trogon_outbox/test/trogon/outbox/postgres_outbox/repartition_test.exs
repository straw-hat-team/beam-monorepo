defmodule Trogon.Outbox.PostgresOutbox.RepartitionTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Partition, Relay, Repartition}

  test "refuses to change the partition count while an event has no cursor at all", %{prefix: prefix} do
    append!(prefix, "source-a", "e1")

    assert_raise ArgumentError, ~r/unpublished events/, fn ->
      Repartition.change!(TestRepo, 16, prefix: prefix)
    end
  end

  test "blocks until a writer already appending finishes, committed or not", %{prefix: prefix} do
    open = open_transaction()

    run_in(open, fn ->
      {:ok, _events} = Trogon.Outbox.append(TestRepo, "source-a", "e1", prefix: prefix)
      :ok
    end)

    task = Task.async(fn -> Repartition.change!(TestRepo, 16, prefix: prefix) end)

    assert Task.yield(task, 300) == nil

    finish(open, :rollback)

    assert Task.await(task) == :ok
    assert outbox_partition_count!(prefix) == 16
    assert source_a_rows(prefix) == []
  end

  test "once every event is drained, changes the count with no loss, duplication, or reorder", %{prefix: prefix} do
    Relay.Store.load_cursors!(TestRepo, prefix, "relay-a", Partition.all(8))
    append!(prefix, "source-a", "e1")

    assert_raise ArgumentError, ~r/unpublished events/, fn ->
      Repartition.change!(TestRepo, 16, prefix: prefix)
    end

    drain!(prefix, "relay-a", "source-a")

    assert Repartition.change!(TestRepo, 16, prefix: prefix) == :ok
    assert outbox_partition_count!(prefix) == 16

    [e2] = append!(prefix, "source-a", "e2")

    assert e2.position.seq.value == 2
    assert source_a_rows(prefix) == [{1, "e1"}, {2, "e2"}]
  end

  defp drain!(prefix, relay, source) do
    %Postgrex.Result{rows: [[xid, id, partition]]} =
      SQL.query!(TestRepo, ~s(SELECT xid::text, id, partition FROM "#{prefix}".outbox_events WHERE source = $1), [
        source
      ])

    SQL.query!(
      TestRepo,
      ~s(UPDATE "#{prefix}".outbox_cursors SET xid = $1::xid8, id = $2 WHERE relay = $3 AND partition = $4),
      [String.to_integer(xid), id, relay, partition]
    )
  end

  defp outbox_partition_count!(prefix) do
    %Postgrex.Result{rows: [[count]]} = SQL.query!(TestRepo, ~s[SELECT "#{prefix}".outbox_partition_count()])
    count
  end

  defp source_a_rows(prefix) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(TestRepo, ~s(SELECT seq, payload FROM "#{prefix}".outbox_events WHERE source = $1 ORDER BY seq), [
        "source-a"
      ])

    Enum.map(rows, fn [seq, payload] -> {seq, payload} end)
  end
end
