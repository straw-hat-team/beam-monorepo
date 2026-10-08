defmodule Trogon.Outbox.ObanPro.ChainByWorkerMergesUnrelatedArgsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a chain keyed by worker holds a job with unrelated args until the earlier job finishes" do
    key_a = System.unique_integer([:positive])
    key_b = System.unique_integer([:positive])

    {_pid, name} = ObanInstance.start!(name: :"chain_by_worker_#{key_a}", queues: [chain: 5])

    {:ok, job_a} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key_a, "mode" => "slow"}))
    {:ok, job_b} = Oban.insert(name, ChainDefaultWorker.new(%{"key" => key_b, "role" => "unrelated_b"}))

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == "executing" end, 15_000)

    assert Jobs.state(job_b.id) == "suspended"
    assert Counter.get({:ran, key_b, "unrelated_b"}) == 0

    Jobs.wait_until(fn -> Counter.get({:ran, key_a, "slow"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Counter.get({:ran, key_b, "unrelated_b"}) == 1 end, 10_000)

    assert Counter.get({:seq_for, key_a}) < Counter.get({:seq_for, key_b})
  end
end
