defmodule Trogon.Outbox.ObanShortcomings.LifelineDiscardsOrphanOnLastAttemptTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, args: %{"hang" => true}} = job) do
      ObanReply.send(job, {:started, id})

      receive do
        :never_sent -> :ok
      after
        10_000 -> :ok
      end
    end

    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:started, id})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "an orphan on its last attempt is discarded by Lifeline without an error, a job exception, or another run" do
    start_supervised!({Oban, ObanInstance.opts(:last_attempt_node_a, node: "node-a", queues: [relay: 1])})

    %Oban.Job{id: orphan} =
      %{"source" => "order-1", "hang" => true, "reply_to" => ObanReply.encode(self())}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:last_attempt_node_a, &1))

    assert_receive {:started, ^orphan}, 5_000
    :ok = stop_supervised(:last_attempt_node_a)
    assert ObanJobs.state!(orphan) == "executing"

    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      handler_id,
      [[:oban, :job, :exception], [:oban, :job, :stop], [:oban, :plugin, :stop]],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    start_supervised!(
      {Oban,
       ObanInstance.opts(:last_attempt_node_b,
         node: "node-b",
         queues: [relay: 1],
         lifeline: [rescue_after: 200, interval: 50]
       )}
    )

    assert ObanJobs.eventually(fn -> ObanJobs.state!(orphan) == "discarded" end)
    assert_receive {:lifeline_discarded, discarded_ids}, 5_000
    assert orphan in discarded_ids

    %Oban.Job{id: successor} =
      %{"source" => "order-1", "reply_to" => ObanReply.encode(self())}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:last_attempt_node_b, &1))

    assert_receive {:started, ^successor}, 5_000

    refute_received {:started, ^orphan}
    refute_received {:job_event, ^orphan, _event}
    assert ObanJobs.fetch(orphan).errors == []
  end

  def handle_event(
        [:oban, :plugin, :stop],
        _measurements,
        %{plugin: Oban.Lifeline, discarded_jobs: [_ | _] = jobs},
        test_pid
      ) do
    send(test_pid, {:lifeline_discarded, Enum.map(jobs, & &1.id)})
  end

  def handle_event([:oban, :plugin, :stop], _measurements, _meta, _test_pid), do: :ok

  def handle_event([:oban, :job, event], _measurements, %{job: %Oban.Job{id: id}}, test_pid) do
    send(test_pid, {:job_event, id, event})
  end
end
