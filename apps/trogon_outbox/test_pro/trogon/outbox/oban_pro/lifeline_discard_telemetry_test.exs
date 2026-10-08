defmodule Trogon.Outbox.ObanPro.LifelineDiscardTelemetryTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule HookedWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :lifeline_telemetry, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key, "mode" => "slow"}}) do
      Counter.bump({:started, key})
      Process.sleep(5_000)
      :ok
    end

    def process(%Oban.Job{args: %{"mode" => "discard"}}), do: {:discard, "boom"}

    @impl Oban.Pro.Worker
    def after_process(state, %Oban.Job{args: %{"key" => key}}, _result) do
      Counter.bump({:hook, key, state})
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    test_pid = self()
    handler = "lifeline-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler,
      [[:oban, :job, :stop], [:oban, :job, :exception], [:oban, :plugin, :stop]],
      fn event, _measure, meta, _ -> send(test_pid, {:telemetry, event, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  defp job_events(id) do
    receive do
      {:telemetry, [:oban, :job, _] = event, %{job: %{id: ^id}}} -> [event | job_events(id)]
    after
      0 -> []
    end
  end

  defp lifeline_discarded?(id) do
    receive do
      {:telemetry, [:oban, :plugin, :stop], %{plugin: Oban.Pro.Lifeline, discarded_jobs: jobs}} ->
        Enum.any?(jobs, &(&1.id == id)) or lifeline_discarded?(id)

      {:telemetry, _event, _meta} ->
        lifeline_discarded?(id)
    after
      0 -> false
    end
  end

  test "a job discarded by Lifeline emits no job telemetry event and runs no after_process hook, only the plugin stop event names it" do
    key = System.unique_integer([:positive])
    name = :"lifeline_telemetry_dead_#{key}"

    {node_a, ^name} = ObanInstance.start!(name: name, queues: [lifeline_telemetry: 1], shutdown_grace_period: 10)
    {:ok, job} = Oban.insert(name, HookedWorker.new(%{"key" => key, "mode" => "slow"}))
    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 end)

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    ObanInstance.start!(
      name: :"lifeline_telemetry_rescuer_#{key}",
      queues: [lifeline_telemetry: 1],
      lifeline: {Oban.Pro.Lifeline, rescue_interval: 200}
    )

    Jobs.wait_until(fn -> Jobs.state(job.id) == "discarded" end, 10_000)
    Process.sleep(1_000)

    assert job_events(job.id) == []
    assert Counter.get({:hook, key, :discard}) == 0
    assert lifeline_discarded?(job.id)
  end

  test "a job that discards itself emits a job stop event and runs its after_process hook" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"lifeline_telemetry_live_#{key}", queues: [lifeline_telemetry: 1])

    {:ok, job} = Oban.insert(name, HookedWorker.new(%{"key" => key, "mode" => "discard"}))
    Jobs.wait_until(fn -> Jobs.state(job.id) == "discarded" end, 10_000)
    Jobs.wait_until(fn -> Counter.get({:hook, key, :discard}) == 1 end)

    assert [:oban, :job, :stop] in job_events(job.id)
  end
end
