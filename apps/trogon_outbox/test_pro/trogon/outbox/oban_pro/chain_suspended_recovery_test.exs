defmodule Trogon.Outbox.ObanPro.ChainSuspendedRecoveryWorker do
  @moduledoc false
  use Oban.Pro.Worker,
    queue: :chain_suspended,
    max_attempts: 1,
    chain: [by: [args: [:key]], on_discarded: :hold]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "role" => role}, attempt: attempt}) do
    Counter.bump({:attempted, key, role})

    if role == "predecessor" and attempt == 1 do
      {:discard, "boom"}
    else
      Counter.max_update({:finished_at, key, role}, Counter.bump({:order, key}))
      :ok
    end
  end
end

defmodule Trogon.Outbox.ObanPro.ChainSuspendedRecoveryTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Trogon.Outbox.ObanPro.ChainSuspendedRecoveryWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  setup do
    Jobs.truncate!()
    :ok
  end

  defp discard_predecessor_and_hold_successor!(prefix) do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"#{prefix}_#{key}", queues: [chain_suspended: 5])

    {:ok, predecessor} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "predecessor"}))
    {:ok, successor} = Oban.insert(name, Worker.new(%{"key" => key, "role" => "successor"}))

    Jobs.wait_until(fn -> Jobs.state(predecessor.id) == "discarded" end)
    Process.sleep(500)
    assert Jobs.state(successor.id) == "suspended"

    %{name: name, key: key, predecessor: predecessor, successor: successor}
  end

  test "retry_job and retry_all_jobs leave a suspended chain job suspended" do
    %{name: name, key: key, successor: successor} = discard_predecessor_and_hold_successor!(:chain_suspended_retry)

    :ok = Oban.retry_job(name, successor.id)
    {:ok, 0} = Oban.retry_all_jobs(name, where(Oban.Job, [j], j.id == ^successor.id))

    Process.sleep(500)
    assert Jobs.state(successor.id) == "suspended"
    assert Counter.get({:attempted, key, "successor"}) == 0
  end

  test "retrying the discarded predecessor runs it and then releases the held successor in order" do
    %{name: name, key: key, predecessor: predecessor, successor: successor} =
      discard_predecessor_and_hold_successor!(:chain_suspended_retry_head)

    :ok = Oban.retry_job(name, predecessor.id)

    Jobs.wait_until(fn -> Jobs.state(successor.id) == "completed" end, 10_000)
    assert Jobs.state(predecessor.id) == "completed"
    assert Counter.get({:finished_at, key, "predecessor"}) == 1
    assert Counter.get({:finished_at, key, "successor"}) == 2
  end

  test "cancelling a suspended job is the only direct operator action, and it removes the event without running it" do
    %{name: name, key: key, successor: successor} = discard_predecessor_and_hold_successor!(:chain_suspended_cancel)

    :ok = Oban.cancel_job(name, successor.id)

    Process.sleep(500)
    assert Jobs.state(successor.id) == "cancelled"
    assert Counter.get({:attempted, key, "successor"}) == 0
  end
end
