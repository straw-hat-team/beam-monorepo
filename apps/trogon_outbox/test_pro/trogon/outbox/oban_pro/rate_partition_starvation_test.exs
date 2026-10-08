defmodule Trogon.Outbox.ObanPro.RatePartitionStarvationTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.PartitionWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a rate_limit partition with one job waits behind a sibling partition with a large backlog" do
    key = System.unique_integer([:positive])
    noise_key = "noise-#{key}"
    victim_key = "victim-#{key}"

    {_pid, name} =
      ObanInstance.start!(
        name: :"rate_partition_#{key}",
        poll_interval: 100,
        queues: [partition: [limit: 3, rate_limit: [allowed: 1_000, period: 60, partition: [args: :key]]]]
      )

    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :partition)

    for _job <- 1..30 do
      {:ok, _job} = Oban.insert(name, PartitionWorker.new(%{"key" => noise_key}))
    end

    {:ok, victim} = Oban.insert(name, PartitionWorker.new(%{"key" => victim_key}))

    Jobs.wait_until(fn -> Counter.get({:finish, noise_key}) > 0 end, 2_000)

    assert Jobs.state(victim.id) == "available"
    assert Counter.get({:finish, victim_key}) == 0

    Jobs.wait_until(fn -> Counter.get({:finish, victim_key}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(victim.id) == "completed" end)
  end
end
