defmodule Trogon.Outbox.ObanPro.InsertAllAppliesChainTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChainDefaultWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "insert_all holds the second chained job of the same call until the first finishes" do
    key_a = System.unique_integer([:positive])
    key_b = System.unique_integer([:positive])

    {_pid, name} = ObanInstance.start!(name: :"insert_all_chain_#{key_a}", queues: [chain: 5])

    [job_a, job_b] =
      Oban.insert_all(name, [
        ChainDefaultWorker.new(%{"key" => key_a, "mode" => "slow"}),
        ChainDefaultWorker.new(%{"key" => key_b, "role" => "second"})
      ])

    assert Jobs.state(job_b.id) == "suspended"

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == "executing" end, 10_000)

    assert Jobs.state(job_b.id) == "suspended"
    assert Counter.get({:ran, key_b, "second"}) == 0

    Jobs.wait_until(fn -> Counter.get({:ran, key_a, "slow"}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Counter.get({:ran, key_b, "second"}) == 1 end, 10_000)

    assert Counter.get({:seq_for, key_a}) < Counter.get({:seq_for, key_b})
  end
end
