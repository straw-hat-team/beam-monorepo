defmodule Trogon.Outbox.PostgresOutbox.TransactionPoolerTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Relay

  @pooler_url System.get_env("TROGON_OUTBOX_PGBOUNCER_URL")

  if is_nil(@pooler_url) do
    @moduletag skip:
                 "set TROGON_OUTBOX_PGBOUNCER_URL to a PgBouncer in transaction pool mode in front of the test database"
  end

  @pooler_url @pooler_url || ""

  defmodule PooledRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
  end

  setup do
    Application.put_env(:trogon_outbox, PooledRepo, url: @pooler_url, pool_size: 5)
    start_supervised!(PooledRepo)
    on_exit(fn -> Application.delete_env(:trogon_outbox, PooledRepo) end)
    :ok
  end

  defp pooler_connection do
    uri = URI.parse(@pooler_url)
    [username, password] = String.split(uri.userinfo, ":", parts: 2)

    [
      hostname: uri.host,
      port: uri.port,
      database: String.trim_leading(uri.path, "/"),
      username: username,
      password: password
    ]
  end

  test "append commits through a transaction-mode pooler the same as a direct connection", %{prefix: prefix} do
    {:ok, events} =
      PooledRepo.transaction(fn ->
        {:ok, events} = Trogon.Outbox.append(PooledRepo, "source-a", ["through-the-pooler"], prefix: prefix)
        events
      end)

    assert [%{payload: "through-the-pooler"}] = events
  end

  test "a transaction-mode pooler hands a connection's next statement to a different backend once the old one is gone" do
    pooled_opts = Keyword.merge(pooler_connection(), pool_size: 1, backoff_type: :stop)
    {:ok, pooled} = Postgrex.start_link(pooled_opts)
    {:ok, admin} = Postgrex.start_link(TestRepo.config())

    pid_before = backend_pid!(pooled)
    %Postgrex.Result{} = Postgrex.query!(admin, "SELECT pg_terminate_backend($1)", [pid_before])
    pid_after = backend_pid!(pooled)

    refute pid_after == pid_before

    GenServer.stop(pooled, :normal, 1_000)
    GenServer.stop(admin, :normal, 1_000)
  end

  # The pooler notices a dead server connection asynchronously, so a statement sent right after the
  # kill can land on the closing connection and surface as admin_shutdown instead of quietly getting
  # a fresh backend. PoolerGuard's own sampling retries past exactly this; this test does too.
  defp backend_pid!(conn, attempts_left \\ 5) do
    %Postgrex.Result{rows: [[pid]]} = Postgrex.query!(conn, "SELECT pg_backend_pid()", [])
    pid
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] ->
      if attempts_left > 1, do: backend_pid!(conn, attempts_left - 1), else: reraise(error, __STACKTRACE__)
  end

  # PoolerGuard's own decision logic is covered deterministically by pooler_guard_test.exs, and the
  # real pooler's backend-reassignment mechanism is covered deterministically by the test below this
  # one. What's left for an end-to-end test is the wiring between them: that Relay.start_link actually
  # calls the guard and turns :pooled into the {:error, %ArgumentError{}} a caller sees. Forcing that
  # here still means winning a race against PoolerGuard's own 15ms-paced sampling from outside the
  # relay process, and OrbStack's documented network jitter can stall either side of that race by more
  # than its whole window. A handful of attempts, each a fresh relay against a fresh killer, turns an
  # occasional single-attempt miss into a vanishingly unlikely one, without the test staying silent
  # about what it's doing.
  test "a relay refuses to start when its own connection goes through a transaction-mode pooler", %{prefix: prefix} do
    Process.flag(:trap_exit, true)

    relay_opts = [
      repo: TestRepo,
      prefix: prefix,
      relay: "pooled",
      publisher: {Trogon.Outbox.TestSupport.TestPublisher, test_pid: self(), tag: :pooled},
      connection: pooler_connection(),
      pooler_guard: true
    ]

    assert force_pooler_rejection(relay_opts, 3) == :detected
  end

  defp force_pooler_rejection(relay_opts, attempts_left) do
    killer = spawn_backend_killer()
    result = Relay.start_link(relay_opts)
    stop_backend_killer(killer)

    case result do
      {:error, reason} ->
        assert {%ArgumentError{message: message}, _stacktrace} = reason
        assert message =~ "transaction-mode pooler"
        :detected

      {:ok, pid} ->
        Process.unlink(pid)
        Process.exit(pid, :kill)

        if attempts_left > 1 do
          force_pooler_rejection(relay_opts, attempts_left - 1)
        else
          :not_detected
        end
    end
  end

  # PoolerGuard detects pooling by watching its own connection's backend pid change across the
  # handful of statements it samples right after start. Left alone, that change depends on
  # PgBouncer happening to hand out a different free backend, which is a coin flip under light
  # load. This forces it: as soon as the relay's connection shows up in pg_stat_activity
  # (identified by the application_name the relay always sets), we kill that backend out from
  # under it, so PgBouncer has no choice but to hand the connection's next statement to a fresh
  # one, and we keep doing that for the whole sampling window so a kill that lands mid-statement
  # (which PoolerGuard now retries past rather than treating as inconclusive) still leaves rounds
  # to observe the change. The admin connection is opened and proven live before the relay even
  # starts, so connection setup never eats into the race against the relay's own 15ms rounds, and
  # the window is bounded well short of the point where the relay moves on to using the
  # connection for anything else (loading cursors, taking the lock).
  @backend_killer_window 300

  defp spawn_backend_killer do
    {:ok, admin} = Postgrex.start_link(TestRepo.config())
    %Postgrex.Result{} = Postgrex.query!(admin, "SELECT 1", [])

    Task.async(fn ->
      deadline = System.monotonic_time(:millisecond) + @backend_killer_window
      result = backend_killer_loop(admin, MapSet.new(), deadline)
      GenServer.stop(admin, :normal, 1_000)
      result
    end)
  end

  # A round's own queries run on the admin connection, not the relay's, so they aren't normally in
  # the line of fire; this still guards against a transient error on the admin side itself ending
  # the loop early instead of just skipping the round.
  defp backend_killer_loop(admin, killed, deadline) do
    killed =
      case Postgrex.query(
             admin,
             "SELECT pid FROM pg_stat_activity WHERE datname = current_database() AND application_name = 'trogon_outbox_relay'",
             []
           ) do
        {:ok, %Postgrex.Result{rows: rows}} ->
          Enum.reduce(rows, killed, fn [pid], killed ->
            if MapSet.member?(killed, pid) do
              killed
            else
              Postgrex.query(admin, "SELECT pg_terminate_backend($1)", [pid])
              MapSet.put(killed, pid)
            end
          end)

        {:error, _reason} ->
          killed
      end

    if System.monotonic_time(:millisecond) >= deadline do
      killed
    else
      receive do
        :stop -> killed
      after
        0 -> backend_killer_loop(admin, killed, deadline)
      end
    end
  end

  defp stop_backend_killer(task) do
    send(task.pid, :stop)
    Task.await(task, 1_000)
  end
end
