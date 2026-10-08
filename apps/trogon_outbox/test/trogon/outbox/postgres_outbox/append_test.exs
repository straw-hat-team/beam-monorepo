defmodule Trogon.Outbox.PostgresOutbox.AppendTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Event, MessageId, Migration}

  for strategy <- [:counter, :advisory_lock] do
    @strategy strategy

    test "#{strategy}: concurrent writers with random rollbacks commit a gapless seq per source", %{prefix: prefix} do
      outcomes =
        1..40
        |> Enum.map(fn n ->
          Task.async(fn ->
            source = "source-#{rem(n, 3)}"

            TestRepo.transaction(fn ->
              {:ok, [event]} =
                Trogon.Outbox.append(TestRepo, source, "writer-#{n}", prefix: prefix, strategy: @strategy)

              Process.sleep(Enum.random(0..5))
              if rem(n, 4) == 0, do: TestRepo.rollback(:aborted), else: {source, event.position.seq.value}
            end)
          end)
        end)
        |> Task.await_many(30_000)

      committed = for {:ok, {source, seq}} <- outcomes, do: {source, seq}

      for {source, seqs} <- Enum.group_by(committed, &elem(&1, 0), &elem(&1, 1)) do
        assert Enum.sort(seqs) == Enum.to_list(1..length(seqs))
        assert stored_seqs(prefix, source) == Enum.to_list(1..length(seqs))
      end

      assert length(committed) == 30
    end

    test "#{strategy}: a multi-event append takes consecutive seqs with ids in seq order", %{prefix: prefix} do
      append!(prefix, "source-a", "first", strategy: @strategy)
      events = append!(prefix, "source-a", ["second", "third", "fourth"], strategy: @strategy)

      assert Enum.map(events, & &1.position.seq.value) == [2, 3, 4]
      assert Enum.map(events, & &1.payload) == ["second", "third", "fourth"]
      assert Enum.map(events, & &1.cursor.id) == Enum.sort(Enum.map(events, & &1.cursor.id))
      assert events |> Enum.map(& &1.cursor.xid) |> Enum.uniq() |> length() == 1
    end
  end

  test "appending outside a transaction raises", %{prefix: prefix} do
    assert_raise ArgumentError, ~r/inside a transaction/, fn ->
      Trogon.Outbox.append(TestRepo, "source-a", "payload", prefix: prefix)
    end
  end

  test "the advisory lock strategy refuses repeatable read, where it would read a stale seq", %{prefix: prefix} do
    assert_raise ArgumentError, ~r/read committed/, fn ->
      TestRepo.transaction(fn ->
        SQL.query!(TestRepo, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
        Trogon.Outbox.append(TestRepo, "source-a", "payload", prefix: prefix, strategy: :advisory_lock)
      end)
    end
  end

  test "the message id is stable from source and seq and parses back", %{prefix: prefix} do
    [event] = append!(prefix, "tenant:42", "payload")
    message_id = Event.message_id(event)

    assert to_string(message_id) == "tenant:42:1"
    assert MessageId.parse("tenant:42:1") == {:ok, message_id}
    assert MessageId.parse("tenant") == {:error, :invalid_message_id}
  end

  test "every event of a source lands in the partition the database assigns to it", %{prefix: prefix} do
    events = Enum.flat_map(1..20, &append!(prefix, "source-#{&1}", "payload"))

    for event <- events do
      assert event.partition == Trogon.Outbox.partition_of(TestRepo, event.position.source, prefix: prefix)
      assert event.partition.value in 0..7
    end

    assert Trogon.Outbox.partition_count(TestRepo, prefix: prefix) == 8
  end

  test "the migration records its version and rolls back to nothing", %{prefix: prefix} do
    assert Migration.migrated_version(TestRepo, prefix: prefix) == Migration.current_version()

    Ecto.Migrator.run(TestRepo, [{1, Trogon.Outbox.TestSupport.OutboxMigration}], :down,
      all: true,
      prefix: prefix,
      log: false
    )

    assert Migration.migrated_version(TestRepo, prefix: prefix) == 0

    %Postgrex.Result{rows: [[tables]]} =
      SQL.query!(TestRepo, "SELECT count(*) FROM pg_tables WHERE schemaname = $1 AND tablename LIKE 'outbox_%'", [
        prefix
      ])

    assert tables == 0
  end

  defp stored_seqs(prefix, source) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(TestRepo, ~s(SELECT seq FROM "#{prefix}".outbox_events WHERE source = $1 ORDER BY seq), [source])

    List.flatten(rows)
  end
end
