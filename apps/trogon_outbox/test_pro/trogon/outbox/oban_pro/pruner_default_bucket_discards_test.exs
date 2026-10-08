defmodule Trogon.Outbox.ObanPro.PrunerDefaultBucketDiscardsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "DynamicPruner max_len deletes a discarded job to make room for completed jobs in an unrelated queue" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"pruner_bucket_#{key}", queues: [chain: 5, counter: 5])
    :ok = ObanInstance.await_notifier!(name)

    {:ok, discarded} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key, "mode" => "discard"}))
    Jobs.wait_until(fn -> Jobs.state(discarded.id) == "discarded" end)

    completed_ids =
      for n <- 1..5 do
        {:ok, job} = Oban.insert(name, CounterWorker.new(%{"key" => "completed-#{n}"}))
        job.id
      end

    for id <- completed_ids, do: Jobs.wait_until(fn -> Jobs.state(id) == "completed" end)

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    pruner =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPruner, name, mode: {:max_len, 5}, schedule: "* * * * *")

    send(pruner, :prune)

    Jobs.wait_until(fn -> Jobs.state(discarded.id) == nil end)

    for id <- completed_ids, do: assert(Jobs.state(id) == "completed")
  end
end
