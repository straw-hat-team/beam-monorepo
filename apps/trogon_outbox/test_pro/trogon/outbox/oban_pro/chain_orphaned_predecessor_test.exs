defmodule Trogon.Outbox.ObanPro.ChainOrphanedPredecessorWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :chain_orphaned, max_attempts: 3, chain: [by: [args: [:key]]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "role" => role} = args}) do
    Counter.bump({:started, key, role})

    if role == "first" and Counter.get({:started, key, role}) == 1 do
      Process.sleep(Map.get(args, "sleep_ms", 0))
    end

    Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.ChainOrphanedPredecessorTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainOrphanedPredecessorWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a successor stays suspended while its predecessor is orphaned by a dead node and runs only after the rescued predecessor completes" do
    key = System.unique_integer([:positive])
    name = :"chain_orphaned_#{key}"

    {node_a, ^name} =
      ObanInstance.start!(name: name, queues: [chain_orphaned: 5], shutdown_grace_period: 10)

    {:ok, first} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "first", "sleep_ms" => 30_000}))
    {:ok, second} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "second"}))

    Jobs.wait_until(fn -> Counter.get({:started, key, "first"}) == 1 end)
    assert Jobs.state(second.id) == "suspended"

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    assert Jobs.state(first.id) == "executing"
    assert Jobs.state(second.id) == "suspended"

    {_pid, _node_b} =
      ObanInstance.start!(
        name: :"chain_orphaned_node_b_#{key}",
        queues: [chain_orphaned: 5],
        plugins: [{Oban.Pro.Lifeline, rescue_interval: 200}]
      )

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 15_000)

    assert Counter.get({:started, key, "first"}) == 2
    assert Counter.get({:started, key, "second"}) == 1
    assert Counter.get({:finished_at, key, "first"}) == 1
    assert Counter.get({:finished_at, key, "second"}) == 2
  end
end
