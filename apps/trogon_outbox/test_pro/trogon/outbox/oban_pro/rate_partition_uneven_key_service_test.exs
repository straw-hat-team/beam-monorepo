defmodule Trogon.Outbox.ObanPro.RatePartitionUnevenKeyServiceTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.PartitionWorker

  @hot_keys 4
  @jobs_per_hot_key 5

  setup do
    Jobs.truncate!()
    :ok
  end

  test "with rate quota to spare, some partition keys drain their whole backlog while other keys with an equal backlog have not run at all" do
    key = System.unique_integer([:positive])
    hot_keys = for index <- 1..@hot_keys, do: "hot-#{index}-#{key}"

    {_pid, name} =
      ObanInstance.start!(
        name: :"partition_key_window_#{key}",
        queues: [partition: [local_limit: 1, rate_limit: [allowed: 1_000, period: 60, partition: [args: :key]]]]
      )

    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :partition)

    TestRepo.transaction(fn ->
      for hot_key <- hot_keys, _job <- 1..@jobs_per_hot_key do
        {:ok, _job} = Oban.insert(name, PartitionWorker.new(%{"key" => hot_key}))
      end
    end)

    Jobs.wait_until(
      fn -> Enum.count(hot_keys, &(Counter.get({:finish, &1}) == @jobs_per_hot_key)) >= 2 end,
      20_000
    )

    finished_hot = Enum.map(hot_keys, &Counter.get({:finish, &1}))
    assert Enum.member?(finished_hot, 0)

    Jobs.wait_until(fn -> Enum.all?(hot_keys, &(Counter.get({:finish, &1}) == @jobs_per_hot_key)) end, 20_000)
  end
end
