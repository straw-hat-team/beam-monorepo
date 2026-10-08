defmodule Trogon.Outbox.ObanShortcomings.PrunerDeletesCompletedJobsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"broker_up" => false}}), do: {:error, :broker_unavailable}
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "completed and discarded jobs older than max_age are deleted, leaving nothing to replay or audit" do
    start_supervised!({Oban, ObanInstance.opts(:pruner_node, queues: [relay: 1])})

    [published, lost, recent] =
      for args <- [%{"event_id" => "evt-1"}, %{"event_id" => "evt-2", "broker_up" => false}, %{"event_id" => "evt-3"}] do
        %Oban.Job{id: id} = Oban.insert!(:pruner_node, PublishWorker.new(args))
        id
      end

    assert ObanJobs.eventually(fn ->
             Enum.map([published, lost, recent], &ObanJobs.state!/1) == ["completed", "discarded", "completed"]
           end)

    :ok = stop_supervised(:pruner_node)

    ObanJobs.backdate!(published, :scheduled_at, 120)
    ObanJobs.backdate!(lost, :discarded_at, 120)

    start_supervised!({Oban, ObanInstance.opts(:pruner_node, pruner: [max_age: 60, interval: 50])})

    assert ObanJobs.eventually(fn -> ObanJobs.fetch(published) == nil and ObanJobs.fetch(lost) == nil end)
    assert ObanJobs.state!(recent) == "completed"
    assert ObanJobs.count!() == 1
  end
end
