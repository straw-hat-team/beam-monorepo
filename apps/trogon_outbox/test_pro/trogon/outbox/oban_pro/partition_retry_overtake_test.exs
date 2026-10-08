defmodule Trogon.Outbox.ObanPro.PartitionRetryOvertakeTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.RetryOvertakeWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a later job in the same global_limit partition completes while an earlier job waits out its retry backoff" do
    key = System.unique_integer([:positive])
    queue_opts = [limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]

    {_pid, name} = ObanInstance.start!(name: :"partition_retry_#{key}", queues: [partition_retry: queue_opts])
    :ok = ObanInstance.await_producer!(name, :partition_retry)

    {:ok, predecessor} = Oban.insert(name, RetryOvertakeWorker.new(%{"key" => key, "role" => "predecessor"}))
    Jobs.wait_until(fn -> Jobs.state(predecessor.id) == "retryable" end)

    {:ok, _overtaker} = Oban.insert(name, RetryOvertakeWorker.new(%{"key" => key, "role" => "overtaker"}))
    Jobs.wait_until(fn -> Counter.get({:completed, key, "overtaker"}) == 1 end)

    assert Jobs.state(predecessor.id) == "retryable"
    assert Counter.get({:completed, key, "predecessor"}) == 0
  end
end
