defmodule Trogon.Outbox.ObanShortcomings.QueueSignalLostWithoutListenerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply
  alias Trogon.Outbox.TestSupport.PoolHealth

  @name :queue_signal_node

  defmodule PublishThenWaitWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id, self()})

      receive do
        :finish -> ObanReply.send(job, {:finished, id})
      after
        10_000 -> {:error, :finish_signal_never_arrived}
      end

      :ok
    end
  end

  setup do
    ObanJobs.truncate!()

    on_exit(fn ->
      allow_connections!(true)
      PoolHealth.await_healthy!(TestRepo, 20_000)
    end)

    :ok
  end

  test "resume_queue returns :ok while the notifier is reconnecting, and the queue stays paused" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: [limit: 1, paused: true]])})

    :ok = ObanInstance.await_notifier!(@name)

    listeners = listener_pids()
    assert listeners != []

    allow_connections!(false)
    SQL.query!(TestRepo, "SELECT pg_terminate_backend(pid) FROM unnest($1::int[]) AS pid", [listeners])
    assert ObanJobs.eventually(fn -> listener_pids() == [] end)

    assert :ok = Oban.resume_queue(@name, queue: :relay)
    assert listener_pids() == []

    allow_connections!(true)
    assert ObanJobs.eventually(fn -> listener_pids() != [] end, 10_000)
    PoolHealth.await_healthy!(TestRepo)

    assert Oban.check_queue(@name, queue: :relay).paused

    assert :ok = Oban.resume_queue(@name, queue: :relay)
    assert ObanJobs.eventually(fn -> not Oban.check_queue(@name, queue: :relay).paused end)
  end

  test "cancel_job returns :ok while the notifier is reconnecting, and the executing job keeps running" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: 1])})
    :ok = ObanInstance.await_notifier!(@name)

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "reply_to" => ObanReply.encode(self())}
      |> PublishThenWaitWorker.new()
      |> then(&Oban.insert!(@name, &1))

    assert_receive {:published, ^id, worker}, 5_000

    allow_connections!(false)
    SQL.query!(TestRepo, "SELECT pg_terminate_backend(pid) FROM unnest($1::int[]) AS pid", [listener_pids()])
    assert ObanJobs.eventually(fn -> listener_pids() == [] end)

    assert :ok = Oban.cancel_job(@name, id)
    assert ObanJobs.state!(id) == "cancelled"
    assert listener_pids() == []

    allow_connections!(true)
    assert ObanJobs.eventually(fn -> listener_pids() != [] end, 10_000)
    PoolHealth.await_healthy!(TestRepo)

    assert Process.alive?(worker)
    send(worker, :finish)
    assert_receive {:finished, ^id}, 5_000
    assert ObanJobs.state!(id) == "cancelled"
  end

  test "the same cancel_job with the notifier listening kills the executing job" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: 1])})
    :ok = ObanInstance.await_notifier!(@name)

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "reply_to" => ObanReply.encode(self())}
      |> PublishThenWaitWorker.new()
      |> then(&Oban.insert!(@name, &1))

    assert_receive {:published, ^id, worker}, 5_000
    ref = Process.monitor(worker)

    assert :ok = Oban.cancel_job(@name, id)
    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 5_000
    assert ObanJobs.state!(id) == "cancelled"
  end

  # Postgres refuses to change ALLOW_CONNECTIONS for the database a session is connected to, so
  # the change runs from the maintenance database.
  defp allow_connections!(allowed?) do
    config = TestRepo.config()
    {:ok, admin} = Postgrex.start_link(Keyword.merge(config, database: "postgres", pool_size: 1))

    try do
      Postgrex.query!(admin, ~s(ALTER DATABASE "#{config[:database]}" WITH ALLOW_CONNECTIONS #{allowed?}), [])
    after
      GenServer.stop(admin)
    end
  end

  defp listener_pids do
    TestRepo
    |> SQL.query!("SELECT pid FROM pg_stat_activity WHERE datname = current_database() AND query LIKE 'LISTEN%'")
    |> Map.fetch!(:rows)
    |> List.flatten()
  end
end
