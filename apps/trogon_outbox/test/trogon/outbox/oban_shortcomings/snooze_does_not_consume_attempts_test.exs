defmodule Trogon.Outbox.ObanShortcomings.SnoozeDoesNotConsumeAttemptsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule WaitingWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{attempt: attempt, meta: meta, args: %{"snoozes" => snoozes}} = job) do
      snoozed = Map.get(meta, "snoozed", 0)
      ObanReply.send(job, {:ran, attempt, snoozed})

      if snoozed < snoozes, do: {:snooze, 0}, else: :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a job with max_attempts 1 can snooze repeatedly without ever being discarded" do
    start_supervised!({Oban, ObanInstance.opts(:snooze_attempts, queues: [relay: 1])})

    %Oban.Job{id: id} =
      %{"snoozes" => 5, "reply_to" => ObanReply.encode(self())}
      |> WaitingWorker.new()
      |> then(&Oban.insert!(:snooze_attempts, &1))

    runs =
      for _run <- 0..5 do
        receive do
          {:ran, attempt, snoozed} -> {attempt, snoozed}
        after
          5_000 -> flunk("the snoozing job did not run again in time")
        end
      end

    assert runs == [{1, 0}, {1, 1}, {1, 2}, {1, 3}, {1, 4}, {1, 5}]
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)

    job = ObanJobs.fetch(id)
    assert job.max_attempts == 1
    assert job.attempt == 1
    assert job.meta["snoozed"] == 5
  end
end
