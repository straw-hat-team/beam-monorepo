defmodule Trogon.Outbox.ObanPro.ChainRetrySnoozeWorker do
  @moduledoc false
  use Oban.Pro.Worker, queue: :chain_retry_snooze, max_attempts: 3, chain: [by: [args: [:key]]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "mode" => "error_once"}, attempt: 1}) do
    Counter.bump({:attempted, key, "predecessor"})
    {:error, "boom"}
  end

  def process(%Oban.Job{args: %{"key" => key, "mode" => "snooze_once", "role" => role}}) do
    if Counter.bump({:attempted, key, role}) == 1 do
      {:snooze, 1}
    else
      Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
      :ok
    end
  end

  def process(%Oban.Job{args: %{"key" => key, "role" => role}}) do
    Counter.bump({:attempted, key, role})
    Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
    :ok
  end

  @impl Oban.Worker
  def backoff(_job), do: 1
end

defmodule Trogon.Outbox.ObanPro.ChainRetrySnoozeHoldsSuccessorTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainRetrySnoozeWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  setup do
    Jobs.truncate!()
    :ok
  end

  for mode <- ["error_once", "snooze_once"] do
    test "a successor stays suspended while its chain predecessor waits after #{mode} and runs after it" do
      key = System.unique_integer([:positive])
      {_pid, name} = ObanInstance.start!(name: :"chain_retry_snooze_#{key}", queues: [])

      {:ok, predecessor} =
        Oban.insert(name, Worker.new(%{"key" => key, "role" => "predecessor", "mode" => unquote(mode)}))

      {:ok, successor} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "successor"}))
      assert Jobs.state(successor.id) == "suspended"

      :ok = ObanInstance.await_notifier!(name)
      :ok = Oban.start_queue(name, queue: :chain_retry_snooze, limit: 5)

      Jobs.wait_until(fn -> Jobs.state(predecessor.id) in ["retryable", "scheduled"] end)
      assert Jobs.state(successor.id) == "suspended"
      assert Counter.get({:attempted, key, "successor"}) == 0

      Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end, 15_000)

      assert Counter.get({:finished_at, key, "predecessor"}) == 1
      assert Counter.get({:finished_at, key, "successor"}) == 2
    end
  end
end
