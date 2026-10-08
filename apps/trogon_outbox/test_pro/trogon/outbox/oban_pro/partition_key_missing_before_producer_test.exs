defmodule Trogon.Outbox.ObanPro.PartitionKeyMissingBeforeProducerWorker do
  @moduledoc false
  use Oban.Worker, queue: :partition_before_producer, max_attempts: 1

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key, "seq" => seq}}) do
    order = Counter.bump({:run_order, key})
    Counter.max_update({:ran_at, key, seq}, order)
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.PartitionKeyMissingBeforeProducerTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.PartitionKeyMissingBeforeProducerWorker, as: Worker
  alias Trogon.Outbox.ObanPro.TestRepo

  @queue :partition_before_producer
  @queue_opts [local_limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]

  setup do
    Jobs.truncate!()
    :ok
  end

  defp has_partition_key?(id) do
    %Postgrex.Result{rows: [[present]]} =
      TestRepo.query!("SELECT meta ? 'partition_key' FROM public.oban_jobs WHERE id = $1", [id])

    present
  end

  defp insert!(name, key, seq) do
    {:ok, job} = Oban.insert(name, Worker.new(%{"key" => key, "seq" => seq}))
    job
  end

  defp start_nodes!(prefix, key) do
    {_pid, inserter} = ObanInstance.start!(name: :"#{prefix}_inserter_#{key}", queues: [])
    first = insert!(inserter, key, 1)

    {_pid, runner} = ObanInstance.start!(name: :"#{prefix}_runner_#{key}", queues: [{@queue, @queue_opts}])
    :ok = ObanInstance.await_producer!(runner, @queue)

    %{inserter: inserter, runner: runner, first: first}
  end

  test "a job inserted before any producer of its partitioned queue exists never runs, while a later job for the same key does" do
    key = System.unique_integer([:positive])
    %{runner: runner, first: first} = start_nodes!(:partition_missing, key)

    refute has_partition_key?(first.id)

    later = insert!(runner, key, 2)
    assert has_partition_key?(later.id)

    Jobs.wait_until(fn -> Jobs.state(later.id) == "completed" end, 5_000)
    Process.sleep(3_000)

    assert Jobs.state(first.id) == "available"
    assert Counter.get({:ran_at, key, 1}) == 0
    assert Counter.get({:ran_at, key, 2}) == 1
  end

  test "an inserting node that saw no producer keeps inserting jobs without a partition key after the producer starts" do
    key = System.unique_integer([:positive])
    %{inserter: inserter, runner: runner, first: first} = start_nodes!(:partition_cached, key)

    second = insert!(inserter, key, 2)
    from_runner = insert!(runner, key, 3)

    refute has_partition_key?(first.id)
    refute has_partition_key?(second.id)
    assert has_partition_key?(from_runner.id)

    Jobs.wait_until(fn -> Jobs.state(from_runner.id) == "completed" end, 5_000)
    Process.sleep(1_000)

    assert Jobs.state(first.id) == "available"
    assert Jobs.state(second.id) == "available"
  end

  test "Lifeline repairs the missing partition key, and the stranded job then runs after the later job it should have preceded" do
    key = System.unique_integer([:positive])
    %{runner: runner, first: first} = start_nodes!(:partition_repaired, key)

    later = insert!(runner, key, 2)
    Jobs.wait_until(fn -> Jobs.state(later.id) == "completed" end, 5_000)
    assert Jobs.state(first.id) == "available"

    Jobs.wait_until(fn -> Oban.Peer.leader?(runner) end)
    ObanInstance.start_plugin!(Oban.Pro.Lifeline, runner, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" end, 10_000)

    assert has_partition_key?(first.id)
    assert Counter.get({:ran_at, key, 2}) == 1
    assert Counter.get({:ran_at, key, 1}) == 2
  end
end
