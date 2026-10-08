defmodule Trogon.Outbox.ObanPro.WorkflowAppendPipelineTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Workflow
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule StepWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :workflow_append, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key, "sleep_ms" => sleep_ms}, meta: %{"name" => name}}) do
      Counter.bump({:started, key, name})
      Process.sleep(sleep_ms)
      Counter.bump({:order, key, name}, Counter.bump({:finished, key}))
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"workflow_append_#{key}", queues: [workflow_append: 5])
    %{key: key, name: name}
  end

  defp step(key, sleep_ms), do: StepWorker.new(%{"key" => key, "sleep_ms" => sleep_ms})

  defp find(jobs, name), do: Enum.find(jobs, &(&1.meta["name"] == name))

  test "a job appended behind a dependency that is still executing waits for it and runs after it", %{
    key: key,
    name: name
  } do
    [first] =
      Workflow.new()
      |> Workflow.add(:e1, step(key, 1_000))
      |> then(&Oban.insert_all(name, &1))

    Jobs.wait_until(fn -> Counter.get({:started, key, "e1"}) == 1 end)

    jobs =
      first
      |> Workflow.append()
      |> Workflow.add(:e2, step(key, 0), deps: [:e1])
      |> then(&Oban.insert_all(name, &1))

    second = find(jobs, "e2")
    assert Jobs.state(second.id) == "suspended"

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)
    assert Counter.get({:order, key, "e1"}) == 1
    assert Counter.get({:order, key, "e2"}) == 2
  end

  test "a job appended behind a dependency that already completed stays suspended until Lifeline repairs the workflow",
       %{key: key, name: name} do
    [first] =
      Workflow.new()
      |> Workflow.add(:e1, step(key, 0))
      |> then(&Oban.insert_all(name, &1))

    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" end)

    [second] =
      first
      |> Workflow.append()
      |> Workflow.add(:e2, step(key, 0), deps: [:e1])
      |> then(&Oban.insert_all(name, &1))

    Process.sleep(3_000)

    assert Jobs.state(second.id) == "suspended"
    assert Counter.get({:started, key, "e2"}) == 0

    TestRepo.query!(
      "UPDATE public.oban_workflows SET inserted_at = now() - interval '5 minutes', started_at = now() - interval '5 minutes' WHERE id = $1",
      [second.meta["workflow_id"]]
    )

    ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)
    assert Counter.get({:started, key, "e2"}) == 1
  end

  test "two appends that both name the same tail as their dependency run at the same time and can finish out of order",
       %{key: key, name: name} do
    [first] =
      Workflow.new()
      |> Workflow.add(:e1, step(key, 300))
      |> then(&Oban.insert_all(name, &1))

    [second] =
      first
      |> Workflow.append()
      |> Workflow.add(:e2, step(key, 1_000), deps: [:e1])
      |> then(&Oban.insert_all(name, &1))

    [third] =
      first
      |> Workflow.append()
      |> Workflow.add(:e3, step(key, 0), deps: [:e1])
      |> then(&Oban.insert_all(name, &1))

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" and Jobs.state(third.id) == "completed" end, 10_000)

    assert Counter.get({:order, key, "e3"}) == 2
    assert Counter.get({:order, key, "e2"}) == 3
  end

  test "appending with check_deps: false behind a name that was never inserted, while the workflow is still running, cancels the job without running it",
       %{key: key, name: name} do
    [first] =
      Workflow.new()
      |> Workflow.add(:e1, step(key, 1_000))
      |> then(&Oban.insert_all(name, &1))

    Jobs.wait_until(fn -> Counter.get({:started, key, "e1"}) == 1 end)

    [orphan] =
      first
      |> Workflow.append(check_deps: false)
      |> Workflow.add(:e3, step(key, 0), deps: [:e2])
      |> then(&Oban.insert_all(name, &1))

    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" end)
    Jobs.wait_until(fn -> Jobs.state(orphan.id) == "cancelled" end, 20_000)

    assert Counter.get({:started, key, "e3"}) == 0
    assert TestRepo.query!("SELECT attempt FROM public.oban_jobs WHERE id = $1", [orphan.id]).rows == [[0]]
  end
end
