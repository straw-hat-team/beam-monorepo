defmodule Trogon.Outbox.ObanPro.ChainDiscardHoldRescuedByLifelineTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainByArgsHoldWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  defp discard_predecessor_and_hold_successor!(prefix) do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"#{prefix}_#{key}", queues: [chain_hold: 5])
    :ok = ObanInstance.await_notifier!(name)

    {:ok, predecessor} = Oban.insert(name, ChainByArgsHoldWorker.new(%{"key" => key, "mode" => "discard"}))
    {:ok, successor} = Oban.insert(name, ChainByArgsHoldWorker.new(%{"key" => key, "role" => "successor"}))

    Jobs.wait_until(fn -> Jobs.state(predecessor.id) == "discarded" end)
    Process.sleep(500)

    assert Jobs.state(successor.id) == "suspended"
    assert Counter.get({:ran, key, "successor"}) == 0

    %{name: name, key: key, predecessor: predecessor, successor: successor}
  end

  test "on_discarded: :hold keeps the successor held after its predecessor is discarded" do
    discard_predecessor_and_hold_successor!(:chain_hold_baseline)
  end

  @tag :pro_behavior_changed
  test "DynamicLifeline runs a successor held by on_discarded: :hold while the discarded predecessor row still exists" do
    %{name: name, key: key, predecessor: predecessor, successor: successor} =
      discard_predecessor_and_hold_successor!(:chain_hold_lifeline)

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Counter.get({:ran, key, "successor"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end)

    assert Jobs.state(predecessor.id) == "discarded"
  end

  test "DynamicLifeline runs a successor held by on_discarded: :hold after the discarded predecessor is pruned" do
    %{name: name, key: key, predecessor: predecessor, successor: successor} =
      discard_predecessor_and_hold_successor!(:chain_hold_pruned)

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    Process.sleep(1_100)

    pruner =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPruner, name, mode: {:max_age, 1}, schedule: "* * * * *")

    send(pruner, :prune)

    Jobs.wait_until(fn -> Jobs.state(predecessor.id) == nil end)
    assert Jobs.state(successor.id) == "suspended"

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Counter.get({:ran, key, "successor"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end)
  end
end
