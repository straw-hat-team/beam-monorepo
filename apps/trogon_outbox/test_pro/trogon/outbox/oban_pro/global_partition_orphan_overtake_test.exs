defmodule Trogon.Outbox.ObanPro.GlobalPartitionOrphanOvertakeTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule OrderedWorker do
    @moduledoc false
    use Oban.Worker, queue: :partition_orphan, max_attempts: 3

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"key" => key, "seq" => seq, "sleep_ms" => sleep_ms}}) do
      Counter.bump({:started, key, seq})
      Process.sleep(sleep_ms)
      Counter.bump({:published, key, seq})
      :ok
    end
  end

  @queue_opts [limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]

  setup do
    Jobs.truncate!()
    :ok
  end

  test "once a dead node's producer row is gone, a later job for the same partition key runs while the earlier one is still orphaned" do
    key = System.unique_integer([:positive])
    name_a = :"partition_orphan_a_#{key}"

    {node_a, ^name_a} =
      ObanInstance.start!(name: name_a, queues: [partition_orphan: @queue_opts], shutdown_grace_period: 10)

    :ok = ObanInstance.await_producer!(name_a, :partition_orphan)

    {:ok, first} = Oban.insert(name_a, OrderedWorker.new(%{"key" => key, "seq" => 1, "sleep_ms" => 5_000}))
    Jobs.wait_until(fn -> Counter.get({:started, key, 1}) == 1 end)

    {:ok, second} = Oban.insert(name_a, OrderedWorker.new(%{"key" => key, "seq" => 2, "sleep_ms" => 0}))

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name_a)

    ObanInstance.start!(name: :"partition_orphan_b_#{key}", queues: [partition_orphan: @queue_opts])

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)

    assert Counter.get({:published, key, 2}) == 1
    assert Counter.get({:published, key, 1}) == 0
    assert Jobs.state(first.id) == "executing"
  end
end
