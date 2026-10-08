defmodule Trogon.Outbox.PostgresOutbox.RelayTelemetryTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Relay

  @moduletag partitions: 1

  defp attach(test, events) do
    test_pid = self()
    handler_id = {__MODULE__, test.test, make_ref()}

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _config -> send(test_pid, {:telemetry, event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "lock, acquired fires with the partition it just locked", %{prefix: prefix} = test do
    attach(test, [[:trogon, :outbox, :lock, :acquired]])

    start_relay!(prefix)

    assert_receive {:telemetry, [:trogon, :outbox, :lock, :acquired], %{count: 1}, metadata}, 10_000
    assert metadata.relay == "test"
    assert metadata.partitions == [0]
  end

  test "lock, lost fires and stops the relay when its cursor row disappears out from under it",
       %{prefix: prefix} = test do
    attach(test, [[:trogon, :outbox, :lock, :lost]])

    partition = Trogon.Outbox.partition_of(TestRepo, "source-a", prefix: prefix)
    holder = start_relay!(prefix, tag: :holder, restart: :temporary)
    ref = Process.monitor(holder)

    append!(prefix, "source-a", "first")
    assert_receive {:published, :holder, _batch}, 10_000
    wait_until(fn -> cursor_row(prefix, "test", partition.value) != nil end)

    SQL.query!(TestRepo, ~s(DELETE FROM "#{prefix}".outbox_cursors WHERE relay = $1 AND partition = $2), [
      "test",
      partition.value
    ])

    append!(prefix, "source-a", "second")

    assert_receive {:telemetry, [:trogon, :outbox, :lock, :lost], %{count: 1}, metadata}, 10_000
    assert metadata.relay == "test"
    assert_receive {:DOWN, ^ref, :process, _pid, :lock_lost}, 10_000
  end

  test "health/1 reports cursor lag that clears once the publisher stops failing", %{prefix: prefix} do
    test_pid = self()
    {:ok, gate} = Agent.start_link(fn -> :block end)
    partition = Trogon.Outbox.partition_of(TestRepo, "source-a", prefix: prefix)

    holder =
      start_relay!(prefix,
        tag: :holder,
        handler: fn batch ->
          if Agent.get(gate, & &1) == :block do
            {:error, :blocked}
          else
            send(test_pid, {:published, :holder, batch})
            :ok
          end
        end
      )

    append!(prefix, "source-a", "stuck")

    wait_until(fn -> match?(%{count: 1}, Relay.health(holder).lag[partition]) end)
    assert Relay.health(holder).lag[partition].oldest_event_age_ms >= 0
    assert Relay.health(holder).held == [partition]

    Agent.update(gate, fn _ -> :flow end)
    assert_receive {:published, :holder, _batch}, 10_000

    wait_until(fn -> Relay.health(holder).lag[partition].count == 0 end)
  end

  test "health/1 reports the watermark held back by an open transaction with an xid", %{prefix: prefix} do
    holder = start_relay!(prefix)

    stuck = open_transaction()
    run_in(stuck, fn -> current_xid!() end)

    wait_until(fn -> Relay.health(holder).watermark_holdback_ms > 0 end)

    finish(stuck)
  end
end
