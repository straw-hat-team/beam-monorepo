defmodule Trogon.Outbox.ObanPro.WorkflowDiscardedDepPrunedCancelsTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Workflow
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker
  alias Trogon.Outbox.ObanPro.Workers.WorkflowDiscardWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  defp insert_workflow!(name, key) do
    jobs =
      Workflow.new()
      |> Workflow.add(:a, WorkflowDiscardWorker.new(%{}))
      |> Workflow.add(:b, CounterWorker.new(%{"key" => "workflow-#{key}"}), deps: [:a])
      |> then(&Oban.insert_all(name, &1))

    {Enum.find(jobs, &(&1.meta["name"] == "a")), Enum.find(jobs, &(&1.meta["name"] == "b"))}
  end

  test "a dependent job is cancelled when its dependency is discarded" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_discard_#{key}", queues: [workflow: 5, counter: 5])
    :ok = ObanInstance.await_notifier!(name)

    {job_a, job_b} = insert_workflow!(name, key)
    assert Jobs.state(job_b.id) == "suspended"

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == "discarded" end)
    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "cancelled" end)

    assert Counter.get("workflow-#{key}") == 0
  end

  @tag :pro_behavior_changed
  test "a dependent job whose discarded dependency was pruned stays held until DynamicLifeline cancels it" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_discard_pruned_#{key}", queues: [])
    :ok = ObanInstance.await_notifier!(name)

    {job_a, job_b} = insert_workflow!(name, key)
    assert Jobs.state(job_b.id) == "suspended"

    TestRepo.query!(
      "UPDATE public.oban_jobs SET state = 'discarded', discarded_at = now() - interval '1 hour' WHERE id = $1",
      [job_a.id]
    )

    assert Jobs.state(job_b.id) == "suspended"

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    pruner =
      ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicPruner, name, mode: {:max_age, 1}, schedule: "* * * * *")

    send(pruner, :prune)

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == nil end)
    assert Jobs.state(job_b.id) == "suspended"

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "cancelled" end, 10_000)
    assert Counter.get("workflow-#{key}") == 0
  end
end
