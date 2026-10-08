defmodule Trogon.Outbox.ObanPro.ChainCancelledWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :chain_cancelled, max_attempts: 3, chain: [by: [args: [:key]]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "role" => role} = args}) do
    inflight = Counter.bump({:inflight, key})
    Counter.max_update({:max_inflight, key}, inflight)
    Counter.bump({:started, key, role})
    if args["hold"], do: await_release(key), else: Process.sleep(Map.get(args, "sleep_ms", 0))
    Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
    Counter.bump({:inflight, key}, -1)
    :ok
  end

  defp await_release(key) do
    if Counter.get({:release, key}) == 0 do
      Process.sleep(10)
      await_release(key)
    end
  end
end

defmodule Trogon.Outbox.ObanPro.ChainCancelledHoldWorker do
  @moduledoc false
  use Oban.Pro.Worker,
    queue: :chain_cancelled_hold,
    max_attempts: 3,
    chain: [by: [args: [:key]], on_cancelled: :hold]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "role" => role} = args}) do
    Counter.bump({:started, key, role})
    Process.sleep(Map.get(args, "sleep_ms", 0))
    Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.ChainCancelledJobReleasesChainTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainCancelledHoldWorker, as: HoldWorker
  alias Trogon.Outbox.ObanPro.ChainCancelledWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  setup do
    Jobs.truncate!()
    :ok
  end

  test "after a held job is cancelled, a new job for the chain is inserted runnable and runs alongside the executing predecessor" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_cancelled_middle_#{key}", queues: [chain_cancelled: 5])

    {:ok, first} =
      Oban.insert(name, Worker.new(%{"key" => key, "role" => "first", "hold" => true}))

    Jobs.wait_until(fn -> Counter.get({:started, key, "first"}) == 1 end)

    {:ok, second} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "second"}))
    assert Jobs.state(second.id) == "suspended"

    :ok = Oban.cancel_job(name, second.id)
    assert Jobs.state(second.id) == "cancelled"

    {:ok, third} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "third", "sleep_ms" => 300}))
    assert Jobs.state(third.id) in ["available", "executing"]

    Jobs.wait_until(fn -> Counter.get({:started, key, "third"}) == 1 end)
    assert Jobs.state(first.id) == "executing"

    Jobs.wait_until(fn -> Jobs.state(third.id) == "completed" end, 10_000)
    assert Jobs.state(first.id) == "executing"

    Counter.bump({:release, key})
    Jobs.wait_until(fn -> Jobs.state(first.id) == "completed" end, 10_000)

    assert Counter.get({:max_inflight, key}) == 2
    assert Counter.get({:finished_at, key, "third"}) < Counter.get({:finished_at, key, "first"})
  end

  test "cancelling a chain job before it runs leaves its successor suspended until Lifeline releases it" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_cancelled_head_#{key}", queues: [])

    {:ok, first} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "first"}))
    {:ok, second} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "second"}))
    assert Jobs.state(second.id) == "suspended"

    :ok = Oban.cancel_job(name, first.id)

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :chain_cancelled, limit: 5)

    Process.sleep(1_500)
    assert Jobs.state(first.id) == "cancelled"
    assert Jobs.state(second.id) == "suspended"
    assert Counter.get({:started, key, "second"}) == 0

    ObanInstance.start_plugin!(Oban.Pro.Lifeline, name, rescue_interval: 200)

    Jobs.wait_until(fn -> Jobs.state(second.id) == "completed" end, 10_000)
  end

  test "with on_cancelled: :hold, a job behind a cancelled held job still runs once the job before the cancelled one completes" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"chain_cancelled_hold_#{key}", queues: [chain_cancelled_hold: 5])

    {:ok, first} =
      Oban.insert(name, HoldWorker.new(%{"key" => key, "role" => "first", "sleep_ms" => 1_000}))

    Jobs.wait_until(fn -> Counter.get({:started, key, "first"}) == 1 end)

    {:ok, second} = Oban.insert(name, HoldWorker.new(%{"key" => key, "role" => "second"}))
    :ok = Oban.cancel_job(name, second.id)

    {:ok, third} = Oban.insert(name, HoldWorker.new(%{"key" => key, "role" => "third"}))
    assert Jobs.state(third.id) == "suspended"

    Jobs.wait_until(fn -> Jobs.state(third.id) == "completed" end, 10_000)

    assert Jobs.state(first.id) == "completed"
    assert Jobs.state(second.id) == "cancelled"
    assert Counter.get({:started, key, "second"}) == 0
  end
end
