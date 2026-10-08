defmodule Trogon.Outbox.ObanShortcomings.RetryAfterDiscardReordersTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{attempt: 1, args: %{"fail_first_attempt" => true}}), do: {:error, :broker_unavailable}

    def perform(%Oban.Job{args: %{"sequence" => sequence}} = job) do
      ObanReply.send(job, {:published, sequence})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp insert_event!(name, sequence, opts \\ []) do
    %{
      "source" => "order-1",
      "sequence" => sequence,
      "fail_first_attempt" => Keyword.get(opts, :fail_first_attempt, false),
      "reply_to" => ObanReply.encode(self())
    }
    |> PublishWorker.new()
    |> then(&Oban.insert!(name, &1))
  end

  defp published(count) do
    for _sequence <- 1..count do
      receive do
        {:published, sequence} -> sequence
      after
        5_000 -> flunk("a job was not published in time")
      end
    end
  end

  test "a discarded event retried while later events wait in the queue publishes after them" do
    start_supervised!({Oban, ObanInstance.opts(:retry_discarded, queues: [relay: 1])})
    ObanInstance.await_notifier!(:retry_discarded)

    %Oban.Job{id: first} = insert_event!(:retry_discarded, 1, fail_first_attempt: true)
    assert ObanJobs.eventually(fn -> ObanJobs.state!(first) == "discarded" end)

    :ok = Oban.pause_queue(:retry_discarded, queue: :relay)
    assert ObanJobs.eventually(fn -> Oban.check_queue(:retry_discarded, queue: :relay).paused end)

    insert_event!(:retry_discarded, 2)
    insert_event!(:retry_discarded, 3)
    :ok = Oban.retry_job(:retry_discarded, first)
    assert ObanJobs.state!(first) == "available"

    :ok = Oban.resume_queue(:retry_discarded, queue: :relay)

    assert published(3) == [2, 3, 1]
  end

  test "retry_all_jobs over a queue republishes events that already completed" do
    start_supervised!({Oban, ObanInstance.opts(:retry_all_completed, queues: [relay: 1])})

    %Oban.Job{id: failed} = insert_event!(:retry_all_completed, 1, fail_first_attempt: true)
    %Oban.Job{id: completed} = insert_event!(:retry_all_completed, 2)

    assert published(1) == [2]
    assert ObanJobs.eventually(fn -> ObanJobs.state!(failed) == "discarded" end)
    assert ObanJobs.eventually(fn -> ObanJobs.state!(completed) == "completed" end)

    {:ok, 2} = Oban.retry_all_jobs(:retry_all_completed, where(Oban.Job, queue: "relay"))

    assert Enum.sort(published(2)) == [1, 2]
    assert TestRepo.get!(Oban.Job, completed).attempt == 2
  end
end
