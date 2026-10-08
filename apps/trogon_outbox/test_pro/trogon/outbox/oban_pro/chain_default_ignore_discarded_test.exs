defmodule Trogon.Outbox.ObanPro.ChainDefaultIgnoreDiscardedTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "by default a chain runs the held successor after its predecessor is discarded" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_ignore_discarded_#{key}", queues: [])

    {:ok, predecessor} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key, "mode" => "discard"}))
    {:ok, successor} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key, "role" => "successor"}))

    assert Jobs.state(successor.id) == "suspended"

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :chain, limit: 5)

    Jobs.wait_until(fn -> Jobs.state(predecessor.id) == "discarded" end)
    assert Counter.get({:ran, key, "predecessor"}) == 1

    Jobs.wait_until(fn -> Counter.get({:ran, key, "successor"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end)
  end
end
