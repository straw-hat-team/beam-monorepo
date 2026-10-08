defmodule Trogon.Outbox.ObanPro.WorkflowCancelledDepCascadesTest do
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

  test "by default a cancelled workflow job cancels every downstream job without running them" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_cancel_#{key}", queues: [workflow: 5])

    jobs =
      Workflow.new()
      |> Workflow.add(:a, WorkflowWorker.new(%{"key" => key, "mode" => "cancel"}))
      |> Workflow.add(:b, WorkflowWorker.new(%{"key" => key}), deps: [:a])
      |> Workflow.add(:c, WorkflowWorker.new(%{"key" => key}), deps: [:b])
      |> then(&Oban.insert_all(name, &1))

    [job_a, job_b, job_c] = Enum.map(~w(a b c), fn step -> Enum.find(jobs, &(&1.meta["name"] == step)) end)

    :ok = ObanInstance.await_notifier!(name)

    for job <- [job_a, job_b, job_c] do
      Jobs.wait_until(fn -> Jobs.state(job.id) == "cancelled" end, 10_000)
    end

    assert Counter.get({:ran, key, "a"}) == 1
    assert Counter.get({:ran, key, "b"}) == 0
    assert Counter.get({:ran, key, "c"}) == 0

    for job <- [job_b, job_c] do
      assert [%{"error" => error}] = TestRepo.get!(Oban.Job, job.id).errors
      assert error =~ "cancelled"
    end
  end
end
