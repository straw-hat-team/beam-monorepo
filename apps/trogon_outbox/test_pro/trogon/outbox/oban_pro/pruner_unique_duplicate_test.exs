defmodule Trogon.Outbox.ObanPro.PrunerUniqueDuplicateTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.UniqueWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "pruning a completed unique job lets a duplicate in before its unique period ends" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"pruner_unique_#{key}", queues: [unique: 5])
    :ok = ObanInstance.await_notifier!(name)

    {:ok, original} = Oban.insert(name, UniqueWorker.new(%{"key" => key}))
    Jobs.wait_until(fn -> Jobs.state(original.id) == "completed" end)

    {:ok, deduped} = Oban.insert(name, UniqueWorker.new(%{"key" => key}))
    assert deduped.id == original.id
    assert Jobs.count_by_key(key) == 1

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    Process.sleep(1_100)

    pruner =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPruner, name, mode: {:max_age, 1}, schedule: "* * * * *")

    send(pruner, :prune)

    Jobs.wait_until(fn -> Jobs.state(original.id) == nil end)

    {:ok, duplicate} = Oban.insert(name, UniqueWorker.new(%{"key" => key}))

    refute duplicate.id == original.id
    assert Jobs.count_by_key(key) == 1
  end
end
