defmodule Trogon.Outbox.ObanPro.GlobalLimitPartitionSerializesTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.PartitionWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "global_limit with a partition runs one job per partition key at a time across two nodes" do
    key = System.unique_integer([:positive])
    queue_opts = [limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]

    {_pid, node_a} = ObanInstance.start!(name: :"global_partition_a_#{key}", queues: [partition: queue_opts])
    {_pid, node_b} = ObanInstance.start!(name: :"global_partition_b_#{key}", queues: [partition: queue_opts])
    :ok = ObanInstance.await_producer!(node_a, :partition)
    :ok = ObanInstance.await_producer!(node_b, :partition)

    for _job <- 1..6 do
      {:ok, _job} = Oban.insert(node_a, PartitionWorker.new(%{"key" => key}))
    end

    Jobs.wait_until(fn -> Counter.get({:finish, key}) == 6 end, 15_000)

    assert Counter.get({:max_inflight, key}) == 1
  end
end
