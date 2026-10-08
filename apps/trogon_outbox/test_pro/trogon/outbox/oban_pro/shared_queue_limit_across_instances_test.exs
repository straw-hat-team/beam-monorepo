defmodule Trogon.Outbox.ObanPro.SharedQueueLimitAcrossInstancesTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule SharedWorker do
    @moduledoc false
    use Oban.Worker, queue: :shared_limit, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"run" => run}, conf: conf}) do
      inflight = Counter.bump({:inflight, run})
      Counter.max_update({:max_inflight, run}, inflight)
      Counter.bump({:ran_by, run, conf.name})
      Process.sleep(300)
      Counter.bump({:inflight, run}, -1)
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  defp start_pair!(queue_opts) do
    run = System.unique_integer([:positive])
    {_a, name_a} = ObanInstance.start!(name: :"shared_limit_a_#{run}", queues: [shared_limit: queue_opts])
    {_b, name_b} = ObanInstance.start!(name: :"shared_limit_b_#{run}", queues: [shared_limit: queue_opts])
    :ok = ObanInstance.await_producer!(name_a, :shared_limit)
    :ok = ObanInstance.await_producer!(name_b, :shared_limit)
    {run, name_a, name_b}
  end

  defp run_jobs!(run, name_a, name_b) do
    jobs =
      for i <- 1..6 do
        {:ok, job} = Oban.insert(if(rem(i, 2) == 0, do: name_a, else: name_b), SharedWorker.new(%{"run" => run}))
        job
      end

    Jobs.wait_until(fn -> Enum.all?(jobs, &(Jobs.state(&1.id) == "completed")) end, 15_000)
  end

  test "two Oban instances with different names on the same queue share one global_limit, so they never run more than allowed together" do
    {run, name_a, name_b} = start_pair!(limit: 5, global_limit: [allowed: 1])

    run_jobs!(run, name_a, name_b)

    assert Counter.get({:max_inflight, run}) == 1
  end

  test "a job inserted through one instance name is run by another instance name that serves the same queue" do
    run = System.unique_integer([:positive])
    {_a, name_a} = ObanInstance.start!(name: :"shared_limit_inserter_#{run}", queues: [])
    {_b, name_b} = ObanInstance.start!(name: :"shared_limit_runner_#{run}", queues: [shared_limit: 1])
    :ok = ObanInstance.await_producer!(name_b, :shared_limit)

    {:ok, job} = Oban.insert(name_a, SharedWorker.new(%{"run" => run}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end, 10_000)

    assert Counter.get({:ran_by, run, name_b}) == 1
    assert Counter.get({:ran_by, run, name_a}) == 0
  end

  test "without a global_limit the same two instances run one job each at the same time" do
    {run, name_a, name_b} = start_pair!(limit: 1)

    run_jobs!(run, name_a, name_b)

    assert Counter.get({:max_inflight, run}) == 2
  end
end
