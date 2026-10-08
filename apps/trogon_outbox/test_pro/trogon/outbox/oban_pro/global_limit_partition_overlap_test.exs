defmodule Trogon.Outbox.ObanPro.GlobalLimitPartitionOverlapTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule OverlapWorker do
    @moduledoc false
    use Oban.Worker, queue: :partition_overlap, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"key" => key}}) do
      inflight = Counter.bump({:inflight, key})
      Counter.max_update({:max_inflight, key}, inflight)

      Process.sleep(300)

      Counter.bump({:finish, key})
      Counter.bump({:inflight, key}, -1)
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  test "global_limit allowed: 1 with burst runs several jobs of the same partition key at once" do
    key = System.unique_integer([:positive])
    queue_opts = [limit: 5, global_limit: [allowed: 1, burst: true, partition: [args: :key]]]

    {_pid, name} = ObanInstance.start!(name: :"partition_burst_#{key}", queues: [partition_overlap: queue_opts])
    :ok = ObanInstance.await_producer!(name, :partition_overlap)

    insert_jobs!(name, key, 5)

    Jobs.wait_until(fn -> Counter.get({:finish, key}) == 5 end, 15_000)

    assert Counter.get({:max_inflight, key}) > 1
  end

  test "global_limit allowed: 1 with per_node runs one job of the same partition key per node at once" do
    key = System.unique_integer([:positive])
    queue_opts = [limit: 5, global_limit: [allowed: 1, per_node: true, partition: [args: :key]]]

    {_pid, node_a} = ObanInstance.start!(name: :"partition_per_node_a_#{key}", queues: [partition_overlap: queue_opts])
    {_pid, node_b} = ObanInstance.start!(name: :"partition_per_node_b_#{key}", queues: [partition_overlap: queue_opts])
    :ok = ObanInstance.await_producer!(node_a, :partition_overlap)
    :ok = ObanInstance.await_producer!(node_b, :partition_overlap)

    insert_jobs!(node_a, key, 6)

    Jobs.wait_until(fn -> Counter.get({:finish, key}) == 6 end, 15_000)

    assert Counter.get({:max_inflight, key}) == 2
  end

  defp insert_jobs!(name, key, count) do
    for _job <- 1..count do
      {:ok, _job} = Oban.insert(name, OverlapWorker.new(%{"key" => key}))
    end
  end
end
