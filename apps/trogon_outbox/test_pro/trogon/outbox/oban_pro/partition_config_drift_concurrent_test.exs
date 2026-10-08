defmodule Trogon.Outbox.ObanPro.PartitionConfigDriftConcurrentTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule DriftWorker do
    @moduledoc false
    use Oban.Worker, queue: :partition_drift, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"key" => key, "seq" => seq, "sleep_ms" => sleep_ms}}) do
      inflight = Counter.bump({:inflight, key})
      Counter.max_update({:max_inflight, key}, inflight)
      Process.sleep(sleep_ms)
      Counter.bump({:inflight, key}, -1)
      Counter.bump({:order, key, seq}, Counter.bump({:finished, key}))
      :ok
    end
  end

  @old_opts [limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]
  @new_opts [limit: 5, global_limit: [allowed: 1, partition: [args: [:key, :region]]]]

  setup do
    Jobs.truncate!()
    :ok
  end

  defp partition_key(id) do
    %Postgrex.Result{rows: [[key]]} =
      TestRepo.query!("SELECT meta->>'partition_key' FROM public.oban_jobs WHERE id = $1", [id])

    key
  end

  test "during a rolling deploy that changes the partition config, two jobs for the same key get different partition keys and run at the same time" do
    key = System.unique_integer([:positive])
    {_old, old_name} = ObanInstance.start!(name: :"partition_drift_old_#{key}", queues: [partition_drift: @old_opts])
    {_new, new_name} = ObanInstance.start!(name: :"partition_drift_new_#{key}", queues: [partition_drift: @new_opts])
    :ok = ObanInstance.await_producer!(old_name, :partition_drift)
    :ok = ObanInstance.await_producer!(new_name, :partition_drift)

    {:ok, first} = Oban.insert(old_name, DriftWorker.new(%{"key" => key, "seq" => 1, "sleep_ms" => 5_000}))
    Jobs.wait_until(fn -> Counter.get({:inflight, key}) == 1 end)

    {:ok, second} = Oban.insert(new_name, DriftWorker.new(%{"key" => key, "seq" => 2, "sleep_ms" => 0}))

    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" and Jobs.state(second.id) == "completed" end, 20_000)

    assert partition_key(first.id) != partition_key(second.id)
    assert Counter.get({:max_inflight, key}) == 2
    assert Counter.get({:order, key, 2}) == 1
    assert Counter.get({:order, key, 1}) == 2
  end

  test "with one partition config on every node, the same two jobs run one after the other" do
    key = System.unique_integer([:positive])
    {_a, name_a} = ObanInstance.start!(name: :"partition_same_a_#{key}", queues: [partition_drift: @old_opts])
    {_b, name_b} = ObanInstance.start!(name: :"partition_same_b_#{key}", queues: [partition_drift: @old_opts])
    :ok = ObanInstance.await_producer!(name_a, :partition_drift)
    :ok = ObanInstance.await_producer!(name_b, :partition_drift)

    {:ok, first} = Oban.insert(name_a, DriftWorker.new(%{"key" => key, "seq" => 1, "sleep_ms" => 1_500}))
    Jobs.wait_until(fn -> Counter.get({:inflight, key}) == 1 end)

    {:ok, second} = Oban.insert(name_b, DriftWorker.new(%{"key" => key, "seq" => 2, "sleep_ms" => 0}))

    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" and Jobs.state(second.id) == "completed" end, 10_000)

    assert partition_key(first.id) == partition_key(second.id)
    assert Counter.get({:max_inflight, key}) == 1
    assert Counter.get({:order, key, 1}) == 1
  end
end
