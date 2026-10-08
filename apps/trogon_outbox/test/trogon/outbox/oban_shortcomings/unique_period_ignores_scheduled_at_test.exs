defmodule Trogon.Outbox.ObanShortcomings.UniquePeriodIgnoresScheduledAtTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args], keys: [:event_id]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(:unique_scheduled_node, queues: [relay: [limit: 1, paused: true]])})
    :ok
  end

  defp insert_event(event_id, opts \\ []) do
    Oban.insert(:unique_scheduled_node, PublishWorker.new(%{"event_id" => event_id}, opts))
  end

  test "a duplicate scheduled far enough ahead is still rejected while the original's insert window has not closed" do
    {:ok, %Oban.Job{id: original, conflict?: false}} = insert_event("evt-1", schedule_in: 120)
    assert ObanJobs.state!(original) == "scheduled"

    {:ok, %Oban.Job{id: duplicate, conflict?: true}} = insert_event("evt-1")

    assert duplicate == original
    assert ObanJobs.count!() == 1
  end

  test "a duplicate is accepted once the default 60 second period has passed by inserted_at, even though the original is still scheduled and has not run" do
    {:ok, %Oban.Job{id: original, conflict?: false}} = insert_event("evt-1", schedule_in: 120)
    assert ObanJobs.state!(original) == "scheduled"

    ObanJobs.backdate!(original, :inserted_at, 61)
    assert ObanJobs.state!(original) == "scheduled"

    {:ok, %Oban.Job{id: duplicate, conflict?: false}} = insert_event("evt-1")

    assert duplicate != original
    assert ObanJobs.count!() == 2
    assert ObanJobs.state!(original) == "scheduled"
    assert ObanJobs.state!(duplicate) == "available"
  end
end
