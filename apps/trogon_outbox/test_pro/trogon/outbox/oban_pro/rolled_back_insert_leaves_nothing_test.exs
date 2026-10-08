defmodule Trogon.Outbox.ObanPro.RolledBackInsertLeavesNothingTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Workflow
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.PartitionWorker
  alias Trogon.Outbox.ObanPro.Workers.UniqueWorker
  alias Trogon.Outbox.ObanPro.Workers.WorkflowWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  defp rolled_back(fun) do
    {:error, :rolled_back} = TestRepo.transaction(fn -> fun.() && TestRepo.rollback(:rolled_back) end)
  end

  defp count(sql, params) do
    %Postgrex.Result{rows: [[count]]} = TestRepo.query!(sql, params)
    count
  end

  test "a unique job inserted in a rolled-back business transaction does not block the same job inserted afterwards" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"rollback_unique_#{key}", queues: [unique: 1])

    rolled_back(fn -> {:ok, %Oban.Job{conflict?: false}} = Oban.insert(name, UniqueWorker.new(%{"key" => key})) end)

    {:ok, job} = Oban.insert(name, UniqueWorker.new(%{"key" => key}))

    refute job.conflict?
    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
    assert Counter.get(key) == 1
  end

  test "a workflow inserted in a rolled-back business transaction leaves no workflow row and no jobs" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"rollback_workflow_#{key}", queues: [])

    workflow =
      Workflow.new()
      |> Workflow.add(:a, WorkflowWorker.new(%{"key" => key}))
      |> Workflow.add(:b, WorkflowWorker.new(%{"key" => key}), deps: [:a])

    rolled_back(fn ->
      assert length(Oban.insert_all(name, workflow)) == 2
      assert count("SELECT count(*) FROM public.oban_workflows", []) == 1
    end)

    assert count("SELECT count(*) FROM public.oban_workflows", []) == 0
    assert Jobs.count_by_key(key) == 0
  end

  test "a partitioned job inserted in a rolled-back business transaction does not hold its key's slot" do
    key = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(
        name: :"rollback_partition_#{key}",
        queues: [partition: [limit: 5, global_limit: [allowed: 1, partition: [args: :key]]]]
      )

    :ok = ObanInstance.await_producer!(name, :partition)

    rolled_back(fn -> {:ok, _job} = Oban.insert(name, PartitionWorker.new(%{"key" => key})) end)

    {:ok, job} = Oban.insert(name, PartitionWorker.new(%{"key" => key}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
    assert Counter.get({:finish, key}) == 1
  end
end
