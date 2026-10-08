defmodule Trogon.Outbox.ObanPro.RatePartitionProducerMetaGrowthTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  @queue_opts [limit: 50, rate_limit: [allowed: 100_000, period: 300, partition: [args: :key]]]

  setup do
    Jobs.truncate!()
    :ok
  end

  defp run_keys!(prefix, keys) do
    run = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"#{prefix}_#{run}", queues: [counter: @queue_opts])
    :ok = ObanInstance.await_producer!(name, :counter)

    changesets = for key <- keys, do: CounterWorker.new(%{"key" => "#{run}-#{key}"})
    Oban.insert_all(name, changesets)

    Jobs.wait_until(
      fn ->
        TestRepo.query!("SELECT count(*) FROM public.oban_jobs WHERE state <> 'completed'").rows == [[0]]
      end,
      60_000
    )

    Process.sleep(1_500)

    %Postgrex.Result{rows: [[size]]} =
      TestRepo.query!("SELECT pg_column_size(meta) FROM public.oban_producers WHERE name = $1 AND queue = 'counter'", [
        to_string(name)
      ])

    size
  end

  test "a partitioned rate limit stores a window per distinct key in the producer row, so the row grows with the number of keys in the period" do
    one_key = run_keys!(:rate_meta_one, List.duplicate(1, 2_000))
    Jobs.truncate!()
    many_keys = run_keys!(:rate_meta_many, Enum.to_list(1..2_000))

    assert one_key < 2_000
    assert many_keys > 20 * one_key
  end
end
