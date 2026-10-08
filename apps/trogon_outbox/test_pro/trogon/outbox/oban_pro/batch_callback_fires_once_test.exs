defmodule Trogon.Outbox.ObanPro.BatchCallbackFiresOnceTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.BatchCallbackWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "batch_completed runs exactly once when many jobs in the batch finish at the same time" do
    key = System.unique_integer([:positive])
    batch_id = "batch-#{key}"
    job_count = 25

    {_pid, name} = ObanInstance.start!(name: :"batch_#{key}", queues: [batch: 25])

    batch =
      1..job_count
      |> Enum.map(&BatchCallbackWorker.new(%{"key" => key, "seq" => &1}))
      |> Oban.Pro.Batch.new(batch_id: batch_id)

    assert length(Oban.insert_all(name, batch)) == job_count

    Jobs.wait_until(fn -> Counter.get({:batch_job_ran, key}) == job_count end, 10_000)
    Jobs.wait_until(fn -> Counter.get({:batch_completed, batch_id}) >= 1 end, 10_000)
    Process.sleep(500)

    assert Counter.get({:batch_completed, batch_id}) == 1

    %Postgrex.Result{rows: [[callback_jobs]]} =
      TestRepo.query!(
        "SELECT count(*) FROM public.oban_jobs WHERE meta ->> 'batch_id' = $1 AND meta ->> 'callback' = 'completed'",
        [batch_id]
      )

    assert callback_jobs == 1
  end
end
