# Spike: read outbox inserts from the WAL with pgoutput logical decoding and compare the
# ordering, the open-transaction stall, and the throughput against the snapshot watermark relay.
#
# Needs its own Postgres with wal_level=logical, which the shared trogon-outbox-pg container does
# not have (it runs with wal_level=replica). Start one:
#
#     docker run --name trogon-outbox-pg-logical -d -p 5434:5432 \
#       -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=trogon_outbox_logical_spike \
#       postgres:17-alpine -c wal_level=logical -c max_replication_slots=4 -c max_wal_senders=4
#
# Then run from apps/trogon_outbox:
#
#     MIX_BUILD_PATH=_build_verifyagent mise exec -- mix run bench/spikes/logical_decoding_spike.exs
#
# TROGON_OUTBOX_SPIKE_DATABASE_URL overrides the connection, ecto://postgres:postgres@localhost:5434/trogon_outbox_logical_spike
# by default.

defmodule Trogon.Outbox.Spike.Repo do
  use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
end

defmodule Trogon.Outbox.Spike.Migration do
  use Ecto.Migration

  def up, do: Trogon.Outbox.Migration.up(partitions: 8)
  def down, do: Trogon.Outbox.Migration.down()
end

defmodule Trogon.Outbox.Spike.Decoder do
  @moduledoc """
  Decodes just enough of the pgoutput stream to reconstruct outbox_events inserts: Begin and
  Commit for transaction boundaries, Relation for column names, Insert for the row itself.
  Everything else (Update, Delete, Truncate, Origin, Type) is ignored.

  Acknowledges only on the server's own keepalive requests, the same as the minimal example in
  Postgrex.ReplicationConnection's moduledoc. That advances restart_lsn coarsely rather than after
  every processed message, which this spike's write-up calls out as a gap a real consumer must
  close itself with its own periodic Standby Status Update.
  """

  use Postgrex.ReplicationConnection

  @epoch DateTime.to_unix(~U[2000-01-01 00:00:00Z], :microsecond)

  def start_link(connection_opts, parent, slot, publication, existing?) do
    args = %{parent: parent, slot: slot, publication: publication, existing?: existing?}
    Postgrex.ReplicationConnection.start_link(__MODULE__, args, connection_opts)
  end

  @impl true
  def init(args) do
    {:ok, Map.merge(args, %{step: :disconnected, relations: %{}, xid: nil})}
  end

  @impl true
  def handle_connect(%{existing?: true} = state) do
    {:stream, start_replication(state), [], %{state | step: :streaming}}
  end

  def handle_connect(state) do
    {:query, "CREATE_REPLICATION_SLOT #{state.slot} LOGICAL pgoutput", %{state | step: :create_slot}}
  end

  @impl true
  def handle_result(_results, %{step: :create_slot} = state) do
    {:stream, start_replication(state), [], %{state | step: :streaming}}
  end

  defp start_replication(state) do
    "START_REPLICATION SLOT #{state.slot} LOGICAL 0/0 (proto_version '1', publication_names '#{state.publication}')"
  end

  @impl true
  def handle_data(<<?w, _wal_start::64, _wal_end::64, _clock::64, msg::binary>>, state) do
    {:noreply, decode(msg, state)}
  end

  def handle_data(<<?k, wal_end::64, _clock::64, reply>>, state) do
    messages =
      case reply do
        1 -> [<<?r, wal_end + 1::64, wal_end + 1::64, wal_end + 1::64, now_pg()::64, 0>>]
        0 -> []
      end

    {:noreply, messages, state}
  end

  defp now_pg, do: System.os_time(:microsecond) - @epoch

  defp decode(<<?B, _lsn::64, _commit_ts::64, xid::32>>, state) do
    send(state.parent, {:wal_begin, xid, System.monotonic_time(:microsecond)})
    %{state | xid: xid}
  end

  defp decode(<<?C, _flags::8, _commit_lsn::64, _end_lsn::64, _commit_ts::64>>, state) do
    send(state.parent, {:wal_commit, state.xid, System.monotonic_time(:microsecond)})
    %{state | xid: nil}
  end

  defp decode(<<?R, oid::32, rest::binary>>, state) do
    {_namespace, rest} = cstring(rest)
    {relname, rest} = cstring(rest)
    <<_replica_identity, ncols::16, rest::binary>> = rest
    {columns, _rest} = columns(rest, ncols, [])
    %{state | relations: Map.put(state.relations, oid, {relname, columns})}
  end

  defp decode(<<?I, oid::32, ?N, tuple::binary>>, state) do
    case Map.fetch(state.relations, oid) do
      {:ok, {relname, columns}} ->
        values = tuple_values(tuple)
        row = columns |> Enum.zip(values) |> Map.new()
        send(state.parent, {:wal_insert, state.xid, relname, row, System.monotonic_time(:microsecond)})

      :error ->
        :ok
    end

    state
  end

  defp decode(_other, state), do: state

  defp cstring(bin) do
    {len, 1} = :binary.match(bin, <<0>>)
    <<str::binary-size(^len), 0, rest::binary>> = bin
    {str, rest}
  end

  defp columns(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp columns(<<_flags, rest::binary>>, n, acc) do
    {name, rest} = cstring(rest)
    <<_typeoid::32, _typemod::32, rest::binary>> = rest
    columns(rest, n - 1, [name | acc])
  end

  defp tuple_values(<<ncols::16, rest::binary>>), do: tuple_values(rest, ncols, [])
  defp tuple_values(_rest, 0, acc), do: Enum.reverse(acc)
  defp tuple_values(<<?n, rest::binary>>, n, acc), do: tuple_values(rest, n - 1, [nil | acc])
  defp tuple_values(<<?u, rest::binary>>, n, acc), do: tuple_values(rest, n - 1, [:unchanged_toast | acc])

  defp tuple_values(<<?t, len::32, data::binary-size(len), rest::binary>>, n, acc),
    do: tuple_values(rest, n - 1, [data | acc])
end

defmodule Trogon.Outbox.Spike.OpenTx do
  @moduledoc "A transaction kept open in its own process, same shape as the library's own test helper."

  alias Trogon.Outbox.Spike.Repo

  def open do
    Task.async(fn -> Repo.transaction(&loop/0) end)
  end

  defp loop do
    receive do
      {:run, fun, from, ref} ->
        send(from, {ref, fun.()})
        loop()

      :commit ->
        :committed
    after
      30_000 -> raise "the open transaction was never finished"
    end
  end

  def run_in(task, fun) do
    ref = make_ref()
    send(task.pid, {:run, fun, self(), ref})

    receive do
      {^ref, result} -> result
    after
      10_000 -> raise "the open transaction did not run the step in time"
    end
  end

  def finish(task) do
    send(task.pid, :commit)
    Task.await(task, 10_000)
  end
end

defmodule Trogon.Outbox.Spike do
  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.Spike.{Decoder, Migration, OpenTx, Repo}

  @publication "outbox_spike_pub"
  @slot "outbox_spike_slot"
  @idle_slot "outbox_spike_idle_slot"

  def run do
    {host, port, database, username, password} = connection_params()
    configure_repo!(host, port, database, username, password)
    {:ok, _pid} = Repo.start_link()

    %Postgrex.Result{rows: [[version]]} = SQL.query!(Repo, "SHOW server_version")
    %Postgrex.Result{rows: [[wal_level]]} = SQL.query!(Repo, "SHOW wal_level")
    IO.puts("Postgres #{version}, wal_level=#{wal_level}, database #{database}\n")

    if wal_level != "logical" do
      raise "wal_level is #{wal_level}, not logical; this spike cannot run against this database"
    end

    reinstall!()
    conn_opts = [hostname: host, port: port, database: database, username: username, password: password]

    {:ok, decoder} = Decoder.start_link(conn_opts, self(), @slot, @publication, false)
    warm_up!()

    ordering_proof()
    stall_comparison()
    slot_retention_risk()
    throughput()
    restart_resume(decoder, conn_opts)

    drop_slot_if_exists!(@slot)
    :ok
  end

  defp connection_params do
    url =
      System.get_env(
        "TROGON_OUTBOX_SPIKE_DATABASE_URL",
        "ecto://postgres:postgres@localhost:5434/trogon_outbox_logical_spike"
      )

    uri = URI.parse(url)
    [username, password] = String.split(uri.userinfo, ":")
    database = String.trim_leading(uri.path, "/")
    {uri.host, uri.port, database, username, password}
  end

  defp configure_repo!(host, port, database, username, password) do
    Application.put_env(:trogon_outbox, Repo,
      hostname: host,
      port: port,
      database: database,
      username: username,
      password: password,
      pool_size: 10,
      log: false
    )
  end

  defp reinstall! do
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS public CASCADE")
    SQL.query!(Repo, "CREATE SCHEMA public")
    Ecto.Migrator.run(Repo, [{1, Migration}], :up, all: true, log: false)
    SQL.query!(Repo, "DROP PUBLICATION IF EXISTS #{@publication}")
    SQL.query!(Repo, "CREATE PUBLICATION #{@publication} FOR TABLE outbox_events WITH (publish = 'insert')")
    drop_slot_if_exists!(@slot)
    drop_slot_if_exists!(@idle_slot)
  end

  defp drop_slot_if_exists!(slot) do
    SQL.query!(
      Repo,
      "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name = $1",
      [slot]
    )
  end

  defp warm_up! do
    append!("warm-up", "warm-up")
    [_one] = receive_until([], 1, 5_000) |> inserts()
    IO.puts("Decoder connected and streaming.\n")
  end

  # Mirrors relay_test.exs's "a transaction that appended first but commits last is never
  # skipped": a transaction that takes an earlier xid but commits later must not be delivered
  # before a transaction that took a later xid but committed first.
  defp ordering_proof do
    IO.puts("## Ordering proof\n")

    late = OpenTx.open()
    OpenTx.run_in(late, fn -> Trogon.Outbox.append(Repo, "source-late", "late", []) end)

    append!("source-early", "early")
    OpenTx.finish(late)

    events = receive_until([], 2, 5_000) |> inserts()
    payloads = Enum.map(events, fn {_xid, row, _ts} -> row["payload"] |> decode_payload() end)

    IO.puts("xid-assignment order was source-late (xid taken first), source-early (xid taken second).")
    IO.puts("pgoutput delivered, in stream order: #{inspect(payloads)}")

    if payloads == ["early", "late"] do
      IO.puts("PASS: logical decoding delivered in commit order, not xid-assignment order.\n")
    else
      IO.puts("FAIL: expected [\"early\", \"late\"], got #{inspect(payloads)}\n")
    end
  end

  # Mirrors relay_test.exs's "a long open transaction with an xid delays delivery but loses
  # nothing": an open transaction that has taken an xid holds back pg_snapshot_xmin, which the
  # snapshot watermark relay reads behind, so every source is delayed until it finishes. Logical
  # decoding streams each transaction's own changes as it commits, so a transaction that never
  # touches outbox_events cannot hold back anyone else's rows.
  defp stall_comparison do
    IO.puts("## Open-transaction stall comparison\n")

    long = OpenTx.open()
    OpenTx.run_in(long, fn -> SQL.query!(Repo, "SELECT pg_current_xact_id()") end)

    opened_at = System.monotonic_time(:millisecond)
    Enum.each(1..5, &append!("source-#{&1}", "event-#{&1}"))

    events = receive_until([], 5, 5_000) |> inserts()
    decoded_at = System.monotonic_time(:millisecond)
    delivered_while_open_ms = decoded_at - opened_at

    Process.sleep(2_000)
    held_open_ms = System.monotonic_time(:millisecond) - opened_at
    OpenTx.finish(long)

    payloads = events |> Enum.map(fn {_xid, row, _ts} -> decode_payload(row["payload"]) end) |> Enum.sort()

    IO.puts("the long transaction holds an xid for #{held_open_ms} ms before committing.")
    IO.puts("all 5 inserts were decoded #{delivered_while_open_ms} ms after the long transaction took its xid.")
    IO.puts("decoded payloads: #{inspect(payloads)}")

    IO.puts(
      "the snapshot watermark relay proves the opposite in this same scenario: " <>
        "relay_test.exs, \"a long open transaction with an xid delays delivery but loses nothing\" " <>
        "asserts refute_receive for 1000 ms while the long transaction stays open, and only sees the " <>
        "5 events after finish/1 commits it.\n"
    )
  end

  # An unconsumed slot keeps retaining WAL, demonstrated on a slot this spike creates but never
  # streams from, separate from the slot the decoder is using.
  defp slot_retention_risk do
    IO.puts("## Replication slot WAL retention\n")

    SQL.query!(Repo, "SELECT pg_create_logical_replication_slot($1, 'pgoutput')", [@idle_slot])
    retained_before = retained_bytes(@idle_slot)

    Enum.each(1..200, fn n -> append!("source-retention", "retention-#{n}") end)
    events = receive_until([], 200, 10_000) |> inserts()
    Process.sleep(200)
    retained_after = retained_bytes(@idle_slot)

    IO.puts("idle slot retained_bytes before 200 inserts: #{retained_before}")
    IO.puts("idle slot retained_bytes after 200 inserts the idle slot never consumed: #{retained_after}")
    IO.puts("(the consuming slot, #{@slot}, drained all #{length(events)} of them and does not grow this way.)")

    SQL.query!(Repo, "SELECT pg_drop_replication_slot($1)", [@idle_slot])
    IO.puts("")
  end

  defp retained_bytes(slot) do
    %Postgrex.Result{rows: [[bytes]]} =
      SQL.query!(
        Repo,
        "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) FROM pg_replication_slots WHERE slot_name = $1",
        [slot]
      )

    bytes
  end

  defp throughput do
    IO.puts("## Throughput\n")

    transactions = 50
    rows_per_transaction = 40
    total = transactions * rows_per_transaction

    started = System.monotonic_time(:microsecond)

    Enum.each(1..transactions, fn t ->
      SQL.query!(
        Repo,
        """
        INSERT INTO outbox_events (source, seq, xid, payload)
        SELECT 'source-' || (n % 50), n / 50 + 1, pg_current_xact_id(), $1
          FROM generate_series(0, $2 - 1) AS n
        """,
        [:binary.copy("x", 200), rows_per_transaction],
        timeout: 30_000
      )

      if rem(t, 100) == 0, do: IO.write(".")
    end)

    inserted_at = System.monotonic_time(:microsecond)
    receive_until([], total, 60_000)
    drained_at = System.monotonic_time(:microsecond)

    insert_elapsed = (inserted_at - started) / 1_000_000
    drain_elapsed = (drained_at - started) / 1_000_000

    IO.puts("")
    IO.puts("#{total} events across #{transactions} transactions of #{rows_per_transaction} rows each.")
    IO.puts("insert wall clock: #{Float.round(insert_elapsed, 2)} s, #{round(total / insert_elapsed)} events/s")

    IO.puts(
      "insert + full decode drain wall clock: #{Float.round(drain_elapsed, 2)} s, " <>
        "#{round(total / drain_elapsed)} events/s\n"
    )
  end

  defp restart_resume(decoder, conn_opts) do
    IO.puts("## Restart and resume\n")

    GenServer.stop(decoder)
    append!("source-while-disconnected", "while-disconnected")
    IO.puts("decoder stopped; inserted one event while no consumer was attached to #{@slot}.")

    {:ok, resumed} = Decoder.start_link(conn_opts, self(), @slot, @publication, true)
    {replayed_count, found?} = drain_until_payload("while-disconnected", 10_000)

    IO.puts(
      "reconnected to the same slot; it replayed #{replayed_count} already-delivered events before " <>
        "reaching \"while-disconnected\" again, found? #{found?}, because this spike only acks on the " <>
        "server's keepalive request, never after processing a message, so restart_lsn barely advanced " <>
        "across the whole run. A production consumer must send its own periodic Standby Status Update " <>
        "after real progress to avoid replaying this much already-delivered WAL on every reconnect.\n"
    )

    GenServer.stop(resumed)
  end

  defp drain_until_payload(target, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_drain_until_payload(target, deadline, 0)
  end

  defp do_drain_until_payload(target, deadline, count) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:wal_insert, _xid, relname, row, _ts} ->
        if String.starts_with?(relname, "outbox_events") do
          if decode_payload(row["payload"]) == target do
            {count, true}
          else
            do_drain_until_payload(target, deadline, count + 1)
          end
        else
          do_drain_until_payload(target, deadline, count)
        end

      _other ->
        do_drain_until_payload(target, deadline, count)
    after
      remaining -> {count, false}
    end
  end

  defp append!(source, payload) do
    {:ok, events} =
      Repo.transaction(fn ->
        {:ok, events} = Trogon.Outbox.append(Repo, source, payload, [])
        events
      end)

    events
  end

  defp decode_payload("\\x" <> hex), do: Base.decode16!(hex, case: :lower)
  defp decode_payload(other), do: other

  # The publication is on the partitioned outbox_events table, but pgoutput reports Relation
  # messages under the physical daily partition's name (outbox_events_20261007, for example),
  # not the parent's, since publish_via_partition_root defaults to false. Match on the column
  # shape instead of the name.
  defp inserts(messages) do
    messages
    |> Enum.filter(fn
      {:wal_insert, _xid, relname, _row, _ts} -> String.starts_with?(relname, "outbox_events")
      _other -> false
    end)
    |> Enum.map(fn {:wal_insert, xid, _relname, row, ts} -> {xid, row, ts} end)
  end

  defp receive_until(acc, wanted, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_receive_until(acc, wanted, deadline)
  end

  defp do_receive_until(acc, wanted, deadline) do
    if length(inserts(acc)) >= wanted do
      Enum.reverse(acc)
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        msg -> do_receive_until([msg | acc], wanted, deadline)
      after
        remaining -> raise "timed out waiting for #{wanted} inserts, got #{length(inserts(acc))}"
      end
    end
  end
end

Trogon.Outbox.Spike.run()
