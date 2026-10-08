defmodule Trogon.Outbox.ObanPro.GlobalPartitionDeadNodeHoldsSlotTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule HeldWorker do
    @moduledoc false
    use Oban.Worker, queue: :partition_dead_slot, max_attempts: 3

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

  test "while a dead node's producer row remains, its executing job keeps the partition key's slot and later jobs for the key do not run" do
    key = System.unique_integer([:positive])
    name_a = :"partition_dead_slot_a_#{key}"

    {node_a, ^name_a} =
      ObanInstance.start!(name: name_a, queues: [partition_dead_slot: @queue_opts], shutdown_grace_period: 10)

    :ok = ObanInstance.await_producer!(name_a, :partition_dead_slot)

    {:ok, first} = Oban.insert(name_a, HeldWorker.new(%{"key" => key, "seq" => 1, "sleep_ms" => 30_000}))
    Jobs.wait_until(fn -> Counter.get({:started, key, 1}) == 1 end)

    Supervisor.stop(node_a)

    name_b = :"partition_dead_slot_b_#{key}"
    ObanInstance.start!(name: name_b, queues: [partition_dead_slot: @queue_opts])
    :ok = ObanInstance.await_producer!(name_b, :partition_dead_slot)

    {:ok, second} = Oban.insert(name_b, HeldWorker.new(%{"key" => key, "seq" => 2, "sleep_ms" => 0}))
    {:ok, other} = Oban.insert(name_b, HeldWorker.new(%{"key" => "#{key}-other", "seq" => 1, "sleep_ms" => 0}))

    Jobs.wait_until(fn -> Jobs.state(other.id) == "completed" end, 5_000)
    Process.sleep(3_000)

    assert Jobs.state(first.id) == "executing"
    assert Jobs.state(second.id) == "available"
    assert Counter.get({:started, key, 2}) == 0

    Jobs.delete_producers!(name_a)

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)
  end
end
