defmodule Trogon.Outbox.PostgresOutbox.RelayNetworkPartitionTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.{Batch, LockNamespace, Partition, Relay}
  alias Trogon.Outbox.TestSupport.TcpProxy

  @moduletag partitions: 1

  setup do
    config = TestRepo.config()
    proxy = start_supervised!({TcpProxy, host: config[:hostname] || "localhost", port: config[:port] || 5432})
    {:ok, proxy: proxy}
  end

  defp start_holder!(prefix, proxy, extra_connection \\ []) do
    connection = [hostname: "127.0.0.1", port: TcpProxy.port(proxy)] ++ extra_connection
    start_relay!(prefix, tag: :holder, restart: :temporary, connection: connection)
  end

  test "a frozen connection keeps the session advisory lock, so a standby never takes over", %{
    prefix: prefix,
    proxy: proxy
  } do
    _holder = start_holder!(prefix, proxy)
    wait_until(fn -> relay_backend_pids() != [] end)
    held_by = relay_backend_pids()

    standby = start_relay!(prefix, tag: :standby)
    Process.sleep(200)
    assert Relay.held_partitions(standby) == []

    :ok = TcpProxy.pause(proxy)

    # The proxy withholds every byte in both directions without closing either socket, the same
    # as a silent network partition: nothing tells either side the connection is gone. The holder's
    # own GenServer is blocked inside the frozen query too, so this checks Postgres directly instead
    # of calling into it.
    Process.sleep(3_000)

    assert Relay.held_partitions(standby) == []
    assert relay_backend_pids() == held_by
  end

  test "a short idle_session_timeout on the relay connection bounds standby takeover once the network freezes",
       %{prefix: prefix, proxy: proxy} do
    holder = start_holder!(prefix, proxy, parameters: [idle_session_timeout: "300"])
    wait_until(fn -> Relay.held_partitions(holder) == [Partition.new!(0)] end)

    standby = start_relay!(prefix, tag: :standby)
    Process.sleep(200)
    assert Relay.held_partitions(standby) == []

    :ok = TcpProxy.pause(proxy)

    assert wait_until(fn -> Relay.held_partitions(standby) == [Partition.new!(0)] end, 3_000)

    append!(prefix, "source-a", "after-takeover")
    assert_receive {:published, :standby, %Batch{events: [%{payload: "after-takeover"}]}}, 10_000
  end

  defp relay_backend_pids do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        TestRepo,
        """
        SELECT DISTINCT l.pid FROM pg_locks l
          JOIN pg_database d ON d.oid = l.database
         WHERE l.locktype = 'advisory' AND l.classid::bigint = $1 AND l.objsubid = 2 AND l.granted
           AND d.datname = current_database()
        """,
        [LockNamespace.relay()]
      )

    List.flatten(rows)
  end
end
