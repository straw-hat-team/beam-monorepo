defmodule Trogon.Outbox.ObanShortcomings.UniqueReplaceOverwritesPendingEventTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [keys: [:source], period: :infinity]

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

  defp insert_event!(name, sequence) do
    %{"source" => "order-1", "sequence" => sequence, "reply_to" => ObanReply.encode(self())}
    |> PublishWorker.new(replace: [available: [:args]])
    |> then(&Oban.insert!(name, &1))
  end

  test "a unique conflict with replace overwrites the args of a pending event, so only the later event is ever published" do
    start_supervised!({Oban, ObanInstance.opts(:unique_replace, queues: [relay: [limit: 1, paused: true]])})
    ObanInstance.await_notifier!(:unique_replace)

    %Oban.Job{id: first, conflict?: false} = insert_event!(:unique_replace, 1)
    %Oban.Job{id: second, conflict?: true} = insert_event!(:unique_replace, 2)

    assert second == first
    assert ObanJobs.count!() == 1
    assert TestRepo.get!(Oban.Job, first).args["sequence"] == 2

    :ok = Oban.resume_queue(:unique_replace, queue: :relay)

    assert_receive {:published, 2}, 5_000
    refute_receive {:published, 1}, 200
  end
end
