defmodule Trogon.Outbox.ObanShortcomings.UnmonitoredQueueAccumulatesSilentlyTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      handler_id,
      [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception], [:oban, :queue, :shutdown]],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  def handle_event(event, _measurements, _meta, test_pid), do: send(test_pid, {:telemetry, event})

  test "a queue that no running node declares accumulates available jobs with no error and no telemetry" do
    start_supervised!({Oban, ObanInstance.opts(:idle_queue_node, queues: [other: 1])})

    %Oban.Job{id: id} = Oban.insert!(:idle_queue_node, PublishWorker.new(%{}))

    refute ObanJobs.eventually(fn -> ObanJobs.state!(id) != "available" end, 1_000)
    assert is_nil(Oban.check_queue(:idle_queue_node, queue: :relay))
    refute_received {:telemetry, _event}
  end

  test "a paused queue reports its state through check_queue but still accumulates jobs silently" do
    start_supervised!({Oban, ObanInstance.opts(:paused_queue_node, queues: [relay: [limit: 1, paused: true]])})

    %Oban.Job{id: id} = Oban.insert!(:paused_queue_node, PublishWorker.new(%{}))

    refute ObanJobs.eventually(fn -> ObanJobs.state!(id) != "available" end, 1_000)
    assert %{paused: true, queue: "relay"} = Oban.check_queue(:paused_queue_node, queue: :relay)
    refute_received {:telemetry, _event}
  end
end
