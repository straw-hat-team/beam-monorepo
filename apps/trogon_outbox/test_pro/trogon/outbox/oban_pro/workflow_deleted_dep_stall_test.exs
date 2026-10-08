defmodule Trogon.Outbox.ObanPro.WorkflowDeletedDepStallTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Workflow
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.WorkflowWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a workflow job behind a deleted dependency stays held until DynamicLifeline cancels it" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_stall_#{key}", queues: [])

    jobs =
      Workflow.new()
      |> Workflow.add(:a, WorkflowWorker.new(%{"key" => key}))
      |> Workflow.add(:b, WorkflowWorker.new(%{"key" => key}), deps: [:a])
      |> then(&Oban.insert_all(name, &1))

    job_a = Enum.find(jobs, &(&1.meta["name"] == "a"))
    job_b = Enum.find(jobs, &(&1.meta["name"] == "b"))

    assert Jobs.state(job_a.id) == "available"
    assert Jobs.state(job_b.id) == "suspended"

    Jobs.delete!(job_a.id)

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :workflow, limit: 5)

    Process.sleep(1_000)

    assert Jobs.state(job_b.id) == "suspended"
    assert Counter.get({:ran, key, "b"}) == 0

    TestRepo.query!(
      "UPDATE public.oban_workflows SET inserted_at = now() - interval '5 minutes', started_at = now() - interval '5 minutes' WHERE id = $1",
      [job_b.meta["workflow_id"]]
    )

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "cancelled" end, 10_000)
    assert Counter.get({:ran, key, "b"}) == 0
  end
end
