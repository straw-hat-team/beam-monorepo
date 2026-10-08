defmodule Trogon.Outbox.ObanShortcomings.CancelledJobIsLostTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a cancelled job is never published while later events for its source still are" do
    start_supervised!({Oban, ObanInstance.opts(:cancel_node, queues: [relay: 1])})
    reply_to = ObanReply.encode(self())

    %Oban.Job{id: cancelled} =
      %{"source" => "order-1", "event_id" => "evt-1", "reply_to" => reply_to}
      |> PublishWorker.new(schedule_in: 60)
      |> then(&Oban.insert!(:cancel_node, &1))

    :ok = Oban.cancel_job(:cancel_node, cancelled)

    %Oban.Job{id: later} =
      %{"source" => "order-1", "event_id" => "evt-2", "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:cancel_node, &1))

    assert_receive {:published, ^later}, 5_000
    refute_received {:published, ^cancelled}

    job = ObanJobs.fetch(cancelled)
    assert job.state == "cancelled"
    assert job.cancelled_at
  end
end
