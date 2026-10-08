defmodule Trogon.Outbox.ObanShortcomings.RetryWindowExhaustionTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule AlwaysDownWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 4

    @impl Oban.Worker
    def perform(_job), do: {:error, :broker_unavailable}

    @impl Oban.Worker
    def backoff(%Oban.Job{attempt: attempt}), do: attempt
  end

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"sequence" => sequence}} = job) do
      ObanReply.send(job, {:published, sequence})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "the default backoff without jitter over 19 retries sums to the figure Oban's own docs round to 13 days with jitter" do
    floor_total =
      Enum.sum(for attempt <- 1..19, do: Oban.Backoff.exponential(attempt, mult: 1, max_pow: 100, min_pad: 15))

    assert floor_total == 1_048_859

    thirteen_days_eight_hours = 13 * 24 * 3600 + 8 * 3600
    assert_in_delta floor_total * 1.1, thirteen_days_eight_hours, 2_000
  end

  test "an outage lasting the sum of every attempt's backoff discards the event while a later one for the same source still publishes" do
    start_supervised!({Oban, ObanInstance.opts(:retry_window_node, queues: [relay: 1])})
    reply_to = ObanReply.encode(self())
    max_attempts = 4

    expected_window =
      Enum.sum(for attempt <- 1..(max_attempts - 1), do: AlwaysDownWorker.backoff(%Oban.Job{attempt: attempt}))

    %Oban.Job{id: lost} = Oban.insert!(:retry_window_node, AlwaysDownWorker.new(%{}))

    first_attempted_at =
      ObanJobs.eventually(fn ->
        case ObanJobs.fetch(lost) do
          %{attempt: 1, attempted_at: %DateTime{} = at} -> at
          _ -> nil
        end
      end)

    assert %DateTime{} = first_attempted_at
    assert ObanJobs.eventually(fn -> ObanJobs.state!(lost) == "discarded" end, 15_000)

    job = ObanJobs.fetch(lost)
    assert job.attempt == max_attempts
    assert DateTime.diff(job.discarded_at, first_attempted_at, :second) >= expected_window

    %Oban.Job{id: later} =
      %{"sequence" => 2, "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:retry_window_node, &1))

    assert_receive {:published, 2}, 5_000
    assert ObanJobs.eventually(fn -> ObanJobs.state!(later) == "completed" end)
    assert ObanJobs.state!(lost) == "discarded"
  end
end
