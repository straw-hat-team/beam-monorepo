defmodule Trogon.Outbox.ObanShortcomings.NetworkFaultsBetweenNodeAndDatabaseTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply
  alias Trogon.Outbox.TestSupport.TcpProxy

  defmodule PartitionedRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
  end

  defmodule PublishThenWaitWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, attempt: attempt} = job) do
      ObanReply.send(job, {:published, id, attempt, self()})

      receive do
        :finish -> :ok
      after
        30_000 -> {:error, :finish_signal_never_arrived}
      end
    end
  end

  setup do
    ObanJobs.truncate!()

    config = TestRepo.config()
    proxy = start_supervised!({TcpProxy, host: config[:hostname], port: config[:port] || 5432})

    Application.put_env(
      :trogon_outbox,
      PartitionedRepo,
      config
      |> Keyword.drop([:url, :pool_size])
      |> Keyword.merge(hostname: "127.0.0.1", port: TcpProxy.port(proxy), pool_size: 3)
    )

    on_exit(fn -> Application.delete_env(:trogon_outbox, PartitionedRepo) end)
    start_supervised!(PartitionedRepo)

    test_pid = self()

    :telemetry.attach(
      "partitioned-node-stop",
      [:oban, :job, :stop],
      fn
        _event, _measurements, %{conf: %{name: :partitioned_node}, job: job, state: state}, _config ->
          send(test_pid, {:partitioned_node_stop, job.id, state})

        _event, _measurements, _metadata, _config ->
          :ok
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("partitioned-node-stop") end)
    {:ok, proxy: proxy}
  end

  test "a stale ack from a partitioned node does not overwrite the rescued attempt running elsewhere, though that node reports success",
       %{proxy: proxy} do
    start_supervised!(
      {Oban,
       ObanInstance.opts(:partitioned_node, node: "node-a", repo: PartitionedRepo, peer: false, queues: [relay: 1])}
    )

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "reply_to" => ObanReply.encode(self())}
      |> PublishThenWaitWorker.new()
      |> then(&Oban.insert!(:partitioned_node, &1))

    assert_receive {:published, ^id, 1, partitioned_run}, 5_000

    :ok = TcpProxy.pause(proxy)
    ObanJobs.backdate!(id, :attempted_at, 60)

    start_supervised!(
      {Oban,
       ObanInstance.opts(:healthy_node,
         node: "node-b",
         queues: [relay: 1],
         lifeline: [rescue_after: :timer.seconds(30), interval: 50]
       )}
    )

    assert_receive {:published, ^id, 2, rescued_run}, 5_000
    %Oban.Job{attempted_at: rescued_attempted_at} = ObanJobs.fetch(id)

    send(partitioned_run, :finish)
    refute_receive {:partitioned_node_stop, ^id, _state}, 300
    :ok = TcpProxy.resume(proxy)

    assert_receive {:partitioned_node_stop, ^id, :success}, 10_000
    assert %Oban.Job{state: "executing", attempt: 2, attempted_at: ^rescued_attempted_at} = ObanJobs.fetch(id)

    send(rescued_run, :finish)
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
    assert %Oban.Job{attempt: 2, errors: []} = ObanJobs.fetch(id)
  end

  test "a fetch whose commit reply is lost leaves the fetched job executing with nothing running it, until Lifeline rescues it",
       %{proxy: proxy} do
    start_supervised!(
      {Oban,
       ObanInstance.opts(:partitioned_node,
         node: "node-a",
         repo: PartitionedRepo,
         peer: false,
         stager: [interval: 60_000],
         queues: [relay: 1]
       )}
    )

    :ok = ObanInstance.await_notifier!(:partitioned_node)
    start_supervised!({Oban, ObanInstance.opts(:inserting_node, node: "node-b")})

    :ok = TcpProxy.lose_next_commit_reply(proxy)

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "reply_to" => ObanReply.encode(self())}
      |> PublishThenWaitWorker.new()
      |> then(&Oban.insert!(:inserting_node, &1))

    refute_receive {:published, ^id, _attempt, _run}, 2_000
    assert %Oban.Job{state: "executing", attempt: 1, attempted_by: ["node-a" | _uuid]} = ObanJobs.fetch(id)

    :ok = stop_supervised(:inserting_node)

    start_supervised!(
      {Oban, ObanInstance.opts(:rescuing_node, node: "node-b", lifeline: [rescue_after: 500, interval: 50])}
    )

    # rescue_after: 500 is tight enough that, under load, Lifeline can rescue the job more than
    # once before this test reacts to the first rescue (the same live-job double-rescue proven
    # in lifeline_rescues_orphaned_executing_job_test.exs), so wait directly for the worker to
    # report in rather than polling for attempt to land on exactly 2.
    assert_receive {:published, ^id, attempt, rescued_run}, 10_000
    assert attempt >= 2
    send(rescued_run, :finish)
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
  end
end
