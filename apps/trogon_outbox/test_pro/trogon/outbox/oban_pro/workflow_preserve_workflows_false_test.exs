defmodule Trogon.Outbox.ObanPro.WorkflowPreserveWorkflowsFalseTest do
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

  defp start_with_held_dependent!(prefix, key, final_state) do
    {_pid, name} = ObanInstance.start!(name: :"#{prefix}_#{key}", queues: [counter: 5])
    :ok = ObanInstance.await_notifier!(name)

    jobs =
      Workflow.new()
      |> Workflow.add(:a, WorkflowDiscardWorker.new(%{}))
      |> Workflow.add(:b, CounterWorker.new(%{"key" => "workflow-#{key}"}), deps: [:a])
      |> then(&Oban.insert_all(name, &1))

    job_a = Enum.find(jobs, &(&1.meta["name"] == "a"))
    job_b = Enum.find(jobs, &(&1.meta["name"] == "b"))
    assert Jobs.state(job_b.id) == "suspended"

    TestRepo.query!(
      "UPDATE public.oban_jobs SET state = $2, completed_at = now() - interval '1 hour', discarded_at = now() - interval '1 hour' WHERE id = $1",
      [job_a.id, final_state]
    )

    TestRepo.query!(
      "UPDATE public.oban_workflows SET inserted_at = now() - interval '5 minutes', started_at = now() - interval '5 minutes' WHERE id = $1",
      [job_b.meta["workflow_id"]]
    )

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end)

    %{name: name, job_a: job_a, job_b: job_b}
  end

  defp prune!(name, opts) do
    pruner = ObanInstance.start_plugin!(Oban.Pro.Pruner, name, Keyword.merge([mode: {:max_age, 1}], opts))
    send(pruner, :prune)
    pruner
  end

  test "the default pruner keeps a finished dependency while its dependent is still held, so Lifeline then runs the dependent" do
    key = System.unique_integer([:positive])
    %{name: name, job_a: job_a, job_b: job_b} = start_with_held_dependent!(:wf_preserve_default, key, "completed")

    {:ok, unrelated} = Oban.insert(name, WorkflowDiscardWorker.new(%{}))

    TestRepo.query!(
      "UPDATE public.oban_jobs SET state = 'completed', completed_at = now() - interval '1 hour' WHERE id = $1",
      [unrelated.id]
    )

    prune!(name, [])

    Jobs.wait_until(fn -> Jobs.state(unrelated.id) == nil end)
    assert Jobs.state(job_a.id) == "completed"
    assert Jobs.state(job_b.id) == "suspended"

    ObanInstance.start_plugin!(Oban.Pro.Lifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "completed" end, 10_000)
    assert Counter.get("workflow-#{key}") == 1
  end

  test "with preserve_workflows: false a completed dependency is pruned, the dependent stays held, and Lifeline cancels it without running it" do
    key = System.unique_integer([:positive])
    %{name: name, job_a: job_a, job_b: job_b} = start_with_held_dependent!(:wf_preserve_off, key, "completed")

    prune!(name, preserve_workflows: false)

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == nil end)
    Process.sleep(1_000)
    assert Jobs.state(job_b.id) == "suspended"

    ObanInstance.start_plugin!(Oban.Pro.Lifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "cancelled" end, 10_000)
    assert Counter.get("workflow-#{key}") == 0
  end

  test "with preserve_workflows: false a discarded dependency is pruned and the dependent stays held until Lifeline cancels it" do
    key = System.unique_integer([:positive])
    %{name: name, job_a: job_a, job_b: job_b} = start_with_held_dependent!(:wf_preserve_off_discard, key, "discarded")

    prune!(name, preserve_workflows: false)

    Jobs.wait_until(fn -> Jobs.state(job_a.id) == nil end)
    Process.sleep(1_000)
    assert Jobs.state(job_b.id) == "suspended"

    ObanInstance.start_plugin!(Oban.Pro.Lifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(job_b.id) == "cancelled" end, 10_000)
    assert Counter.get("workflow-#{key}") == 0
  end
end
