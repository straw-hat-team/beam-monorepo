defmodule Trogon.Outbox.ObanShortcomings.NodeClockSkewTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply
  alias Trogon.Outbox.TestSupport.SkewedClockRepo

  defmodule LongPublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, attempt: attempt} = job) do
      ObanReply.send(job, {:started, id, attempt, self()})
      Process.sleep(2_000)
      :ok
    end
  end

  defmodule UniquePublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker], period: 60]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    on_exit(fn -> SkewedClockRepo.skew!(0) end)
    :ok
  end

  defp start_long_job!(name) do
    start_supervised!({Oban, ObanInstance.opts(name, node: "worker-node", peer: false, queues: [relay: 2])})

    %Oban.Job{id: id} =
      %{"source" => "order-1", "reply_to" => ObanReply.encode(self())}
      |> LongPublishWorker.new()
      |> then(&Oban.insert!(name, &1))

    assert_receive {:started, ^id, 1, first_run}, 5_000
    {id, first_run}
  end

  defp start_lifeline_leader!(name, skew_seconds) do
    SkewedClockRepo.skew!(skew_seconds)

    start_supervised!(
      {Oban,
       ObanInstance.opts(name,
         node: "leader-node",
         repo: SkewedClockRepo,
         lifeline: [rescue_after: :timer.seconds(10), interval: 50]
       )}
    )

    assert ObanJobs.eventually(fn -> Oban.Peer.leader?(name) end)
  end

  test "a Lifeline leader whose clock runs ahead rescues a job that is well within rescue_after, so it runs twice" do
    {id, first_run} = start_long_job!(:skew_worker_ahead)
    start_lifeline_leader!(:skew_leader_ahead, 30)

    assert_receive {:started, ^id, 2, second_run}, 2_000
    assert second_run != first_run
    assert Process.alive?(first_run)
  end

  test "the same Lifeline leader with a correct clock leaves that job alone" do
    {id, first_run} = start_long_job!(:skew_worker_correct)
    start_lifeline_leader!(:skew_leader_correct, 0)

    refute_receive {:started, ^id, 2, _second_run}, 1_000
    assert Process.alive?(first_run)
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
  end

  test "a node whose clock runs ahead of the database by more than the unique period inserts a duplicate the other node rejects" do
    start_supervised!({Oban, ObanInstance.opts(:skew_unique_correct)})
    SkewedClockRepo.skew!(120)
    start_supervised!({Oban, ObanInstance.opts(:skew_unique_ahead, repo: SkewedClockRepo, peer: false)})

    event = %{"event_id" => "evt-1"}

    assert {:ok, %Oban.Job{conflict?: false}} = Oban.insert(:skew_unique_correct, UniquePublishWorker.new(event))
    assert {:ok, %Oban.Job{conflict?: true}} = Oban.insert(:skew_unique_correct, UniquePublishWorker.new(event))
    assert {:ok, %Oban.Job{conflict?: false}} = Oban.insert(:skew_unique_ahead, UniquePublishWorker.new(event))

    assert ObanJobs.count!() == 2
  end

  test "a Pruner leader whose clock runs ahead by more than max_age deletes a job the moment it completes" do
    start_supervised!({Oban, ObanInstance.opts(:skew_pruner_worker, peer: false, queues: [relay: 1])})

    %Oban.Job{id: id} = Oban.insert!(:skew_pruner_worker, UniquePublishWorker.new(%{"event_id" => "evt-1"}))
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)

    SkewedClockRepo.skew!(120)

    start_supervised!(
      {Oban, ObanInstance.opts(:skew_pruner_ahead, repo: SkewedClockRepo, pruner: [max_age: 60, interval: 50])}
    )

    assert ObanJobs.eventually(fn -> is_nil(ObanJobs.fetch(id)) end)
  end

  defp leave_live_leader_row!(name) do
    SQL.query!(
      TestRepo,
      """
      INSERT INTO oban_peers (name, node, started_at, expires_at)
      VALUES ($1, 'node-correct', timezone('UTC', now()), timezone('UTC', now()) + interval '30 seconds')
      """,
      [inspect(name)]
    )
  end

  defp leader_node(name) do
    %Postgrex.Result{rows: [[node]]} =
      SQL.query!(TestRepo, "SELECT node FROM oban_peers WHERE name = $1", [inspect(name)])

    node
  end

  test "a node whose clock runs ahead by more than the peer lease deletes a live leader's lease and takes leadership" do
    leave_live_leader_row!(:skew_peer_ahead)
    SkewedClockRepo.skew!(60)

    start_supervised!({Oban, ObanInstance.opts(:skew_peer_ahead, node: "node-ahead", repo: SkewedClockRepo)})

    assert ObanJobs.eventually(fn -> Oban.Peer.leader?(:skew_peer_ahead) end)
    assert leader_node(:skew_peer_ahead) == "node-ahead"
  end

  test "the same node with a correct clock waits for the live leader's lease" do
    leave_live_leader_row!(:skew_peer_correct)

    start_supervised!({Oban, ObanInstance.opts(:skew_peer_correct, node: "node-ahead", repo: SkewedClockRepo)})

    refute ObanJobs.eventually(fn -> Oban.Peer.leader?(:skew_peer_correct) end, 1_000)
    assert leader_node(:skew_peer_correct) == "node-correct"
  end
end
