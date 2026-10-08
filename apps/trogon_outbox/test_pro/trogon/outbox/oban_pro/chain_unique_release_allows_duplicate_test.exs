defmodule Trogon.Outbox.ObanPro.ChainUniqueWorker do
  @moduledoc false
  use Oban.Pro.Worker,
    queue: :chain_unique,
    max_attempts: 1,
    chain: [by: [args: [:key]]],
    unique: [period: 300, keys: [:key, :seq]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "seq" => seq} = args}) do
    Counter.bump({:published, key, seq})
    Process.sleep(Map.get(args, "sleep_ms", 0))
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.ChainUniqueReleaseAllowsDuplicateTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainUniqueWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a unique chained job rejects duplicates while suspended but accepts them once the chain releases it" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_unique_#{key}", queues: [])

    {:ok, _first} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 1}))
    {:ok, second} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 2}))
    assert Jobs.state(second.id) == "suspended"

    {:ok, held_dupe} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 2}))
    assert held_dupe.conflict?
    assert held_dupe.id == second.id

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :chain_unique, limit: 5)

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)

    {:ok, released_dupe} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 2}))
    refute released_dupe.conflict?
    refute released_dupe.id == second.id

    Jobs.wait_until(fn -> Jobs.state(released_dupe.id) == "completed" end, 10_000)
    assert Counter.get({:published, key, 2}) == 2
  end

  test "a unique chained job that was never held keeps rejecting duplicates after it completes" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_unique_head_#{key}", queues: [chain_unique: 5])

    {:ok, head} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 1}))
    Jobs.wait_until(fn -> Jobs.state(head.id) == "completed" end, 10_000)

    {:ok, dupe} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => 1}))
    assert dupe.conflict?
    assert dupe.id == head.id
    assert Counter.get({:published, key, 1}) == 1
  end
end
