defmodule Trogon.Outbox.ObanPro.RecordedOverLimitRerunsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule RecordedWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :recorded, max_attempts: 3, recorded: [limit: 100]

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key, "size" => size}}) do
      Counter.bump({:published, key})
      {:ok, :crypto.strong_rand_bytes(size)}
    end

    @impl Oban.Worker
    def backoff(_job), do: 0
  end

  setup do
    Jobs.truncate!()
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"recorded_#{key}", queues: [recorded: 1])
    %{key: key, name: name}
  end

  test "a recorded job whose return value exceeds the limit fails after its side effect ran, so every retry publishes again",
       %{key: key, name: name} do
    {:ok, job} = Oban.insert(name, RecordedWorker.new(%{"key" => key, "size" => 1_000}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "discarded" end, 10_000)

    assert Counter.get({:published, key}) == 3

    %Postgrex.Result{rows: [[errors]]} =
      Trogon.Outbox.ObanPro.TestRepo.query!("SELECT errors FROM public.oban_jobs WHERE id = $1", [job.id])

    assert length(errors) == 3
    assert Enum.all?(errors, &(&1["error"] =~ "larger than the limit"))
  end

  test "a recorded job whose return value fits the limit publishes once and completes", %{key: key, name: name} do
    {:ok, job} = Oban.insert(name, RecordedWorker.new(%{"key" => key, "size" => 10}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end, 10_000)

    assert Counter.get({:published, key}) == 1
  end
end
