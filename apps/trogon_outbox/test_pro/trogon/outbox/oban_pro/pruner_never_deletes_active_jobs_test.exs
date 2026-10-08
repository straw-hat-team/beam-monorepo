defmodule Trogon.Outbox.ObanPro.PrunerNeverDeletesActiveJobsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "DynamicPruner keeps available and scheduled jobs older than max_age" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"pruner_active_#{key}", queues: [])
    :ok = ObanInstance.await_notifier!(name)

    {:ok, available} = Oban.insert(name, CounterWorker.new(%{"key" => "available-#{key}"}))
    {:ok, scheduled} = Oban.insert(name, CounterWorker.new(%{"key" => "scheduled-#{key}"}, schedule_in: 3_600))

    assert Jobs.state(available.id) == "available"
    assert Jobs.state(scheduled.id) == "scheduled"

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    Process.sleep(1_100)

    pruner =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPruner, name, mode: {:max_age, 1}, schedule: "* * * * *")

    send(pruner, :prune)
    send(pruner, :prune)
    Process.sleep(200)

    assert Jobs.state(available.id) == "available"
    assert Jobs.state(scheduled.id) == "scheduled"
  end
end
