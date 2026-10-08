defmodule Trogon.Outbox.ObanPro.PrioritizerPreservesOrderTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  defp priority(id) do
    %Postgrex.Result{rows: [[priority]]} =
      TestRepo.query!("SELECT priority FROM public.oban_jobs WHERE id = $1", [id])

    priority
  end

  test "DynamicPrioritizer bumps two same-priority jobs together on every tick until both reach 0" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"prioritizer_#{key}", queues: [])
    :ok = ObanInstance.await_notifier!(name)

    {:ok, older} = Oban.insert(name, CounterWorker.new(%{"key" => "older-#{key}"}, priority: 5))
    {:ok, newer} = Oban.insert(name, CounterWorker.new(%{"key" => "newer-#{key}"}, priority: 5))

    assert older.id < newer.id

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    prioritizer =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPrioritizer, name, after: 0, interval: :timer.hours(1))

    for expected <- [4, 3, 2, 1, 0] do
      send(prioritizer, :reprioritize)
      Jobs.wait_until(fn -> priority(older.id) == expected end)
      assert priority(newer.id) == expected
    end

    send(prioritizer, :reprioritize)
    Process.sleep(100)

    assert priority(older.id) == 0
    assert priority(newer.id) == 0
  end
end
