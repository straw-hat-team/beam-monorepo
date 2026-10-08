defmodule Trogon.Outbox.ObanPro.LifelineDiscardsExhaustedOrphanTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :lifeline_exhausted

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"key" => key, "sleep_ms" => sleep_ms}}) do
      Counter.bump({:started, key})
      Process.sleep(sleep_ms)
      Counter.bump({:published, key})
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  test "Lifeline discards a job killed mid-run on its last attempt, so its side effect never runs" do
    %{key: key, job: job} = kill_node_mid_run!(:lifeline_exhausted_last, max_attempts: 1)

    start_rescuer!(key)

    Jobs.wait_until(fn -> Jobs.state(job.id) == "discarded" end, 10_000)
    Process.sleep(500)

    assert Counter.get({:started, key}) == 1
    assert Counter.get({:published, key}) == 0
    assert Jobs.state(job.id) == "discarded"
  end

  test "Lifeline rescues a job killed mid-run with attempts left, and it runs to completion" do
    %{key: key, job: job} = kill_node_mid_run!(:lifeline_exhausted_spare, max_attempts: 2)

    start_rescuer!(key)

    Jobs.wait_until(fn -> Counter.get({:published, key}) == 1 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
    assert Counter.get({:started, key}) == 2
  end

  defp kill_node_mid_run!(prefix, job_opts) do
    key = System.unique_integer([:positive])
    name = :"#{prefix}_#{key}"

    {node_a, ^name} =
      ObanInstance.start!(name: name, queues: [lifeline_exhausted: 1], shutdown_grace_period: 10)

    {:ok, job} = Oban.insert(name, PublishWorker.new(%{"key" => key, "sleep_ms" => 5_000}, job_opts))

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 end)
    assert Jobs.state(job.id) == "executing"

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    assert Jobs.state(job.id) == "executing"
    assert Counter.get({:published, key}) == 0

    %{key: key, job: job}
  end

  defp start_rescuer!(key) do
    ObanInstance.start!(
      name: :"lifeline_exhausted_rescuer_#{key}",
      queues: [lifeline_exhausted: 1],
      lifeline: {Oban.Pro.Lifeline, rescue_interval: 200}
    )
  end
end
