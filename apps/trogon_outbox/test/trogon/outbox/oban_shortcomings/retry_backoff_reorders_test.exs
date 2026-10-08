defmodule Trogon.Outbox.ObanShortcomings.RetryBackoffReordersTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{attempt: 1, args: %{"fail_first_attempt" => true}}), do: {:error, :broker_unavailable}

    def perform(%Oban.Job{args: %{"sequence" => sequence}} = job) do
      ObanReply.send(job, {:published, sequence})
      :ok
    end

    @impl Oban.Worker
    def backoff(_job), do: 2
  end

  defmodule DefaultBackoffWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a failed job retried after backoff lets a later job for the same source publish first" do
    start_supervised!({Oban, ObanInstance.opts(:retry_reorders, queues: [relay: 1])})
    reply_to = ObanReply.encode(self())

    for {sequence, fail_first_attempt} <- [{1, true}, {2, false}] do
      %{
        "source" => "order-1",
        "sequence" => sequence,
        "fail_first_attempt" => fail_first_attempt,
        "reply_to" => reply_to
      }
      |> PublishWorker.new()
      |> then(&Oban.insert!(:retry_reorders, &1))
    end

    published =
      for _sequence <- [1, 2] do
        receive do
          {:published, sequence} -> sequence
        after
          5_000 -> flunk("a job was not published in time")
        end
      end

    assert published == [2, 1]
  end

  test "the default backoff waits at least 15 seconds plus 2 to the power of the attempt" do
    for attempt <- 1..5 do
      floor = 15 + Integer.pow(2, attempt)
      backoff = DefaultBackoffWorker.backoff(%Oban.Job{attempt: attempt, max_attempts: 20})

      assert backoff >= floor
      assert backoff <= floor + trunc(floor * 0.1)
    end
  end
end
