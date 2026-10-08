defmodule Trogon.Outbox.ObanShortcomings.UnknownWorkerDuringDeployTest do
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

  @not_yet_deployed_worker "Trogon.Outbox.ObanShortcomings.NotYetDeployed.PublishWorker"

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a node without the worker module fails the job into backoff while a later event publishes" do
    start_supervised!({Oban, ObanInstance.opts(:old_release_node, queues: [relay: 1])})
    reply_to = ObanReply.encode(self())

    %Oban.Job{id: unknown} =
      %{"source" => "order-1", "event_id" => "evt-1", "reply_to" => reply_to}
      |> Oban.Job.new(worker: @not_yet_deployed_worker, queue: :relay)
      |> then(&Oban.insert!(:old_release_node, &1))

    assert ObanJobs.eventually(fn -> ObanJobs.state!(unknown) == "retryable" end)

    %Oban.Job{id: later} =
      %{"source" => "order-1", "event_id" => "evt-2", "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:old_release_node, &1))

    assert_receive {:published, ^later}, 5_000

    job = ObanJobs.fetch(unknown)
    assert job.state == "retryable"
    assert [%{"error" => error}] = job.errors
    assert error =~ "unknown worker"
    assert DateTime.diff(job.scheduled_at, DateTime.utc_now()) >= 10
  end

  test "a job for an unknown worker that has no attempts left is discarded" do
    start_supervised!({Oban, ObanInstance.opts(:old_release_node, queues: [relay: 1])})

    %Oban.Job{id: unknown} =
      %{"source" => "order-1", "event_id" => "evt-1"}
      |> Oban.Job.new(worker: @not_yet_deployed_worker, queue: :relay, max_attempts: 1)
      |> then(&Oban.insert!(:old_release_node, &1))

    assert ObanJobs.eventually(fn -> ObanJobs.state!(unknown) == "discarded" end)
  end
end
