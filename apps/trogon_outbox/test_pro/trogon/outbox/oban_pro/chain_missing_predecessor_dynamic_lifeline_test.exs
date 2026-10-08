defmodule Trogon.Outbox.ObanPro.ChainMissingPredecessorDynamicLifelineTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a successor held behind a deleted predecessor stays held until DynamicLifeline runs" do
    key_a = System.unique_integer([:positive])
    key_b = System.unique_integer([:positive])

    {_pid, name} = ObanInstance.start!(name: :"chain_missing_predecessor_#{key_a}", queues: [])

    {:ok, predecessor} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key_a, "role" => "predecessor"}))
    {:ok, successor} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key_b, "role" => "successor"}))

    assert Jobs.state(successor.id) == "suspended"

    Jobs.delete!(predecessor.id)

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :chain, limit: 5)

    Process.sleep(1_000)

    assert Jobs.state(successor.id) == "suspended"
    assert Counter.get({:ran, key_b, "successor"}) == 0

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Counter.get({:ran, key_b, "successor"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end)
  end
end
