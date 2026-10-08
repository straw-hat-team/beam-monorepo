defmodule Trogon.Outbox.ObanPro.ChainConcurrentInsertsWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :chain_concurrent, max_attempts: 1, chain: [by: [args: [:key]]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{id: id, args: %{"key" => key}}) do
    inflight = Counter.bump({:inflight, key})
    Counter.max_update({:max_inflight, key}, inflight)
    Process.sleep(50)
    order = Counter.bump({:order, key})
    Counter.max_update({:ran_at, key, id}, order)
    Counter.bump({:inflight, key}, -1)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.ChainConcurrentInsertsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainConcurrentInsertsWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  setup do
    Jobs.truncate!()
    :ok
  end

  test "chained jobs inserted for one key from concurrent transactions run one at a time in id order" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_concurrent_#{key}", queues: [chain_concurrent: 10])

    ids =
      1..8
      |> Task.async_stream(
        fn _index ->
          {:ok, job} =
            TestRepo.transaction(fn ->
              {:ok, job} = Oban.insert(name, Worker.new(%{"key" => key}))
              Process.sleep(:rand.uniform(100))
              job
            end)

          job.id
        end,
        max_concurrency: 8,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, id} -> id end)
      |> Enum.sort()

    Jobs.wait_until(fn -> Counter.get({:order, key}) == 8 end, 15_000)

    assert Counter.get({:max_inflight, key}) == 1
    assert Enum.map(ids, &Counter.get({:ran_at, key, &1})) == Enum.to_list(1..8)
  end

  test "a transaction inserting into a chain blocks a concurrent insert into the same chain until it commits" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_concurrent_block_#{key}", queues: [])

    test_pid = self()

    holder =
      Task.async(fn ->
        {:ok, committing_at} =
          TestRepo.transaction(fn ->
            {:ok, _job} = Oban.insert(name, Worker.new(%{"key" => key}))
            send(test_pid, :first_inserted)
            Process.sleep(1_000)
            System.monotonic_time(:millisecond)
          end)

        committing_at
      end)

    assert_receive :first_inserted, 5_000

    other_key = System.unique_integer([:positive])
    started = System.monotonic_time(:millisecond)
    {:ok, _job} = Oban.insert(name, Worker.new(%{"key" => other_key}))
    unrelated_elapsed = System.monotonic_time(:millisecond) - started

    {:ok, _job} = Oban.insert(name, Worker.new(%{"key" => key}))
    same_key_returned = System.monotonic_time(:millisecond)

    committing_at = Task.await(holder, 5_000)

    assert unrelated_elapsed < 500
    assert same_key_returned >= committing_at
  end

  test "a chained insert rolled back by its transaction does not strand a later job in the same chain" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_concurrent_rollback_#{key}", queues: [])

    {:ok, first} = Oban.insert(name, Worker.new(%{"key" => key}))

    {:error, :rolled_back} =
      TestRepo.transaction(fn ->
        {:ok, _job} = Oban.insert(name, Worker.new(%{"key" => key}))
        TestRepo.rollback(:rolled_back)
      end)

    {:ok, last} = Oban.insert(name, Worker.new(%{"key" => key}))
    assert Jobs.state(last.id) == "suspended"

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :chain_concurrent, limit: 5)

    Jobs.wait_until(fn -> Jobs.state(last.id) == "completed" end, 10_000)
    assert Counter.get({:ran_at, key, first.id}) == 1
    assert Counter.get({:ran_at, key, last.id}) == 2
  end
end
