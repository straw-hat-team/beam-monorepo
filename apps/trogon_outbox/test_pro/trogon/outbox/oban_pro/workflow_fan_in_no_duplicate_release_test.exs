defmodule Trogon.Outbox.ObanPro.WorkflowFanInNoDuplicateReleaseTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Workflow
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.WorkflowWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a fan-in job runs exactly once when both of its dependencies complete at the same time" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_fan_in_#{key}", queues: [workflow: 10])

    jobs =
      Workflow.new()
      |> Workflow.add(:a, WorkflowWorker.new(%{"key" => key}))
      |> Workflow.add(:b, WorkflowWorker.new(%{"key" => key}))
      |> Workflow.add(:c, WorkflowWorker.new(%{"key" => key}), deps: [:a, :b])
      |> then(&Oban.insert_all(name, &1))

    job_c = Enum.find(jobs, &(&1.meta["name"] == "c"))

    :ok = ObanInstance.await_notifier!(name)

    Jobs.wait_until(fn -> Jobs.state(job_c.id) == "completed" end, 10_000)
    Process.sleep(300)

    assert Counter.get({:ran, key, "c"}) == 1
    assert Jobs.state(job_c.id) == "completed"
  end
end
