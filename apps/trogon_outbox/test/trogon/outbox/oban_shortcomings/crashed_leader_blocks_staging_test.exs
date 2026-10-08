defmodule Trogon.Outbox.ObanShortcomings.CrashedLeaderBlocksStagingTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  @lease_ms 1_500

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp leave_crashed_leader_row!(name, lease_ms) do
    SQL.query!(
      TestRepo,
      """
      INSERT INTO oban_peers (name, node, started_at, expires_at)
      VALUES ($1, 'crashed-node', timezone('UTC', now()), timezone('UTC', now()) + make_interval(secs => $2))
      """,
      [inspect(name), lease_ms / 1_000]
    )
  end

  test "a leader that died without releasing its peer row keeps every surviving node from staging until the lease expires" do
    leave_crashed_leader_row!(:surviving_node, @lease_ms)

    start_supervised!(
      {Oban,
       ObanInstance.opts(:surviving_node,
         node: "surviving-node",
         queues: [relay: 1],
         peer: {Oban.Peers.Database, interval: 100}
       )}
    )

    %Oban.Job{id: id} =
      PublishWorker.new(%{}, scheduled_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> then(&Oban.insert!(:surviving_node, &1))

    refute ObanJobs.eventually(fn -> ObanJobs.state!(id) != "scheduled" end, div(@lease_ms, 2))
    refute Oban.Peer.leader?(:surviving_node)

    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end, @lease_ms * 3)
    assert Oban.Peer.leader?(:surviving_node)
  end

  test "a leader's peer row is written with a 30 second lease by default" do
    start_supervised!({Oban, ObanInstance.opts(:default_lease_node, node: "default-lease-node")})

    assert ObanJobs.eventually(fn -> Oban.Peer.leader?(:default_lease_node) end)

    %Postgrex.Result{rows: [[lease_seconds]]} =
      SQL.query!(
        TestRepo,
        "SELECT extract(epoch FROM expires_at - started_at)::int FROM oban_peers WHERE name = $1",
        [inspect(:default_lease_node)]
      )

    assert lease_seconds == 30
  end
end
