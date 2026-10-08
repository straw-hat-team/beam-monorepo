defmodule Trogon.Outbox.ObanShortcomings.DiscardAfterMaxAttemptsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 2

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"broker_up" => false}}), do: {:error, :broker_unavailable}

    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id})
      :ok
    end

    @impl Oban.Worker
    def backoff(_job), do: 0
  end

  setup do
    ObanJobs.truncate!()
    handler_id = {__MODULE__, make_ref()}
    :telemetry.attach(handler_id, [:oban, :job, :exception], &__MODULE__.handle_exception/4, self())

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  def handle_exception(_event, _measurements, %{job: job, state: state}, test_pid) do
    send(test_pid, {:exception, job.id, state})
  end

  test "a job that exhausts max_attempts is discarded and nothing delivers it again" do
    start_supervised!({Oban, ObanInstance.opts(:discard_node, queues: [relay: 1])})
    reply_to = ObanReply.encode(self())

    %Oban.Job{id: lost} =
      %{"event_id" => "evt-1", "broker_up" => false, "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:discard_node, &1))

    assert_receive {:exception, ^lost, :failure}, 5_000
    assert_receive {:exception, ^lost, :discard}, 5_000
    assert ObanJobs.eventually(fn -> ObanJobs.state!(lost) == "discarded" end)

    %Oban.Job{id: later} =
      %{"event_id" => "evt-2", "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:discard_node, &1))

    assert_receive {:published, ^later}, 5_000
    refute_received {:published, ^lost}

    job = ObanJobs.fetch(lost)
    assert job.state == "discarded"
    assert job.attempt == job.max_attempts
    assert length(job.errors) == 2
  end
end
