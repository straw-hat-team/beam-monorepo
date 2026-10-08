defmodule Trogon.Outbox.ObanPro.RatePartition10kKeysTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  @job_count 10_000
  @sample_after_ms 12_000

  setup do
    Jobs.truncate!()
    :ok
  end

  test "partition key cardinality, not job count or the rate_limit allowance, collapses dispatch throughput by roughly two orders of magnitude" do
    low_card_completed = run_and_sample!(:rate_partition_lowcard, 20)
    Jobs.truncate!()
    high_card_completed = run_and_sample!(:rate_partition_highcard, @job_count)

    assert high_card_completed < 500
    assert low_card_completed > 5 * max(high_card_completed, 100)
  end

  test "producer meta grows with every distinct partition key dispatched against and is never compacted within the rate limit period" do
    run = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(
        name: :"rate_partition_meta_#{run}",
        queues: [counter: [limit: 20, rate_limit: [allowed: 100_000, period: 300, partition: [args: :key]]]]
      )

    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :counter)

    changesets = for index <- 1..@job_count, do: CounterWorker.new(%{"key" => "#{run}-#{index}"})
    Oban.insert_all(name, changesets)

    Process.sleep(6_000)
    size_early = meta_size(name)

    Process.sleep(9_000)
    size_later = meta_size(name)

    assert size_later > size_early
  end

  defp run_and_sample!(prefix, key_count) do
    run = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(
        name: :"#{prefix}_#{run}",
        queues: [counter: [limit: 20, rate_limit: [allowed: 100_000, period: 300, partition: [args: :key]]]]
      )

    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :counter)

    changesets = for index <- 1..@job_count, do: CounterWorker.new(%{"key" => "#{run}-#{rem(index, key_count)}"})
    Oban.insert_all(name, changesets)

    Process.sleep(@sample_after_ms)

    %Postgrex.Result{rows: [[completed]]} =
      TestRepo.query!("SELECT count(*) FROM public.oban_jobs WHERE state = 'completed'")

    completed
  end

  defp meta_size(name) do
    %Postgrex.Result{rows: [[size]]} =
      TestRepo.query!(
        "SELECT pg_column_size(meta) FROM public.oban_producers WHERE name = $1 AND queue = 'counter'",
        [to_string(name)]
      )

    size
  end
end
