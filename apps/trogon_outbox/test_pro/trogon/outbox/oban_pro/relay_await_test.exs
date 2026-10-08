defmodule Trogon.Outbox.ObanPro.RelayFlakyWorker do
  @moduledoc false
  use Oban.Worker, queue: :relay_flaky, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: 1}), do: {:error, "boom"}
  def perform(%Oban.Job{args: %{"val" => val}}), do: {:ok, val}

  @impl Oban.Worker
  def backoff(_job), do: 0
end

defmodule Trogon.Outbox.ObanPro.RelayOkWorker do
  @moduledoc false
  use Oban.Worker, queue: :relay_ok, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"val" => val}}), do: {:ok, val}
end

defmodule Trogon.Outbox.ObanPro.RelayAwaitTest do
  use ExUnit.Case, async: false

  alias Oban.Pro.Relay
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.RelayFlakyWorker
  alias Trogon.Outbox.ObanPro.RelayOkWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "default await returns the first transient failure immediately, while the job itself goes on to complete" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"relay_default_#{key}", queues: [relay_flaky: 5])
    :ok = ObanInstance.await_notifier!(name)

    relay = Relay.async(name, RelayFlakyWorker.new(%{"val" => key}))

    assert {:error, _reason} = Relay.await(relay, timeout: 2_000)
    refute Jobs.state(relay.job.id) == "discarded"

    Jobs.wait_until(fn -> Jobs.state(relay.job.id) == "completed" end, 8_000)
  end

  test "await with with_retries: true waits past the transient failure and returns the eventual success" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"relay_retries_#{key}", queues: [relay_flaky: 5])
    :ok = ObanInstance.await_notifier!(name)

    relay = Relay.async(name, RelayFlakyWorker.new(%{"val" => key}))

    assert {:ok, ^key} = Relay.await(relay, with_retries: true, timeout: 8_000)
    Jobs.wait_until(fn -> Jobs.state(relay.job.id) == "completed" end, 2_000)
  end

  test "await_many/2 has no with_retries escape hatch, so a flaky relay in the batch returns its first failure early while a healthy relay in the same batch returns normally" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"relay_many_#{key}", queues: [relay_flaky: 5, relay_ok: 5])
    :ok = ObanInstance.await_notifier!(name)

    relay_fail = Relay.async(name, RelayFlakyWorker.new(%{"val" => key}))
    relay_ok = Relay.async(name, RelayOkWorker.new(%{"val" => key}))

    [result_fail, result_ok] = Relay.await_many([relay_fail, relay_ok], 2_000)

    assert {:error, _reason} = result_fail
    assert result_ok == {:ok, key}

    Jobs.wait_until(fn -> Jobs.state(relay_fail.job.id) == "completed" end, 8_000)
  end
end
