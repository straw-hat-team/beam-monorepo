defmodule Trogon.Outbox.ObanShortcomings.CronTicksAreNotExactlyOnceTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  @every_minute "* * * * *"

  defmodule SweepWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    await_clear_of_minute_boundary()
    :ok
  end

  # Cron's own timer fires on every minute boundary, so each test starts far enough from the next
  # one that only the evaluations it triggers itself can insert jobs.
  defp await_clear_of_minute_boundary do
    %Time{second: second} = Time.utc_now()
    if second > 45, do: Process.sleep(:timer.seconds(61 - second))
  end

  defp start_cron_node!(name) do
    start_supervised!(
      {Oban,
       ObanInstance.opts(name,
         node: "cron-node",
         peer: {Oban.Peers.Database, interval: 100},
         cron: [crontab: [{@every_minute, SweepWorker}]]
       )}
    )
  end

  defp evaluate!(name) do
    cron = Oban.Registry.whereis(name, {:plugin, Oban.Cron})
    send(cron, :evaluate)
    :sys.get_state(cron)
    :ok
  end

  defp leave_live_leader_row!(name) do
    SQL.query!(
      TestRepo,
      """
      INSERT INTO oban_peers (name, node, started_at, expires_at)
      VALUES ($1, 'other-node', timezone('UTC', now()), timezone('UTC', now()) + interval '30 seconds')
      """,
      [inspect(name)]
    )
  end

  defp drop_leader_row!(name), do: SQL.query!(TestRepo, "DELETE FROM oban_peers WHERE name = $1", [inspect(name)])

  test "a leader that evaluates the crontab twice within one minute inserts that minute's job twice" do
    start_cron_node!(:cron_twice)
    assert ObanJobs.eventually(fn -> Oban.Peer.leader?(:cron_twice) end)

    evaluate!(:cron_twice)
    evaluate!(:cron_twice)

    assert [%Oban.Job{meta: %{"cron_expr" => @every_minute}}, %Oban.Job{meta: %{"cron_expr" => @every_minute}}] =
             TestRepo.all(Oban.Job)
  end

  test "a minute evaluated while the node is not leader is skipped, and gaining leadership does not catch it up" do
    leave_live_leader_row!(:cron_skipped)
    start_cron_node!(:cron_skipped)

    evaluate!(:cron_skipped)
    refute Oban.Peer.leader?(:cron_skipped)
    assert ObanJobs.count!() == 0

    drop_leader_row!(:cron_skipped)
    assert ObanJobs.eventually(fn -> Oban.Peer.leader?(:cron_skipped) end)
    Process.sleep(500)
    assert ObanJobs.count!() == 0

    evaluate!(:cron_skipped)
    assert ObanJobs.count!() == 1
  end
end
