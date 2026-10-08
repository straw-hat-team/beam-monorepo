defmodule Trogon.Outbox.ObanShortcomings.PriorityReordersTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

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

  test "a later event with a higher priority publishes before an earlier event for the same source" do
    start_supervised!({Oban, ObanInstance.opts(:priority_node, queues: [relay: [limit: 1, paused: true]])})
    reply_to = ObanReply.encode(self())

    for {sequence, priority} <- [{1, 3}, {2, 0}] do
      %{"source" => "order-1", "sequence" => sequence, "reply_to" => reply_to}
      |> PublishWorker.new(priority: priority)
      |> then(&Oban.insert!(:priority_node, &1))
    end

    :ok = ObanInstance.await_notifier!(:priority_node)
    :ok = Oban.resume_queue(:priority_node, queue: :relay)

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
end
