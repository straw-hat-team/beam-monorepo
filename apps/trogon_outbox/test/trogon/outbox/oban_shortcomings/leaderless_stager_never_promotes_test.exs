defmodule Trogon.Outbox.ObanShortcomings.LeaderlessStagerNeverPromotesTest do
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
    :ok
  end

  test "a node that never becomes leader leaves a due scheduled job stuck at scheduled, with no error and no telemetry" do
    start_supervised!({Oban, ObanInstance.opts(:leaderless_node, peer: false, queues: [relay: 1])})

    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      [:oban, :plugin, :stop],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    due_at = DateTime.add(DateTime.utc_now(), -1, :second)

    %Oban.Job{id: id} =
      PublishWorker.new(%{}, scheduled_at: due_at)
      |> then(&Oban.insert!(:leaderless_node, &1))

    assert ObanJobs.state!(id) == "scheduled"
    refute ObanJobs.eventually(fn -> ObanJobs.state!(id) == "available" end, 500)
    assert ObanJobs.state!(id) == "scheduled"

    assert_received {:plugin_stop, %{plugin: Oban.Stager, staged_count: 0}}
  end

  def handle_event([:oban, :plugin, :stop], _measurements, meta, test_pid) do
    send(test_pid, {:plugin_stop, meta})
  end
end
