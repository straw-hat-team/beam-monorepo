defmodule Trogon.Outbox.ObanShortcomings.UniqueJobsAreNotIdempotencyTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(:unique_node)})
    :ok
  end

  defp insert_event(event_id), do: Oban.insert(:unique_node, PublishWorker.new(%{"event_id" => event_id}))

  test "a duplicate is rejected while the original is still in a unique state" do
    {:ok, %Oban.Job{id: original, conflict?: false}} = insert_event("evt-1")
    {:ok, %Oban.Job{id: duplicate, conflict?: true}} = insert_event("evt-1")

    assert duplicate == original
    assert ObanJobs.count!() == 1
  end

  test "a duplicate is accepted once the original is discarded, because discarded is not a default unique state" do
    {:ok, %Oban.Job{id: original}} = insert_event("evt-1")
    TestRepo.update_all(Oban.Job, set: [state: "discarded", discarded_at: DateTime.utc_now()])

    {:ok, %Oban.Job{id: duplicate, conflict?: false}} = insert_event("evt-1")

    assert duplicate != original
    assert ObanJobs.count!() == 2
  end

  test "a duplicate is accepted once the default 60 second period has passed" do
    {:ok, %Oban.Job{id: original}} = insert_event("evt-1")
    TestRepo.update_all(Oban.Job, set: [state: "completed", completed_at: DateTime.utc_now()])
    ObanJobs.backdate!(original, :inserted_at, 61)

    {:ok, %Oban.Job{id: duplicate, conflict?: false}} = insert_event("evt-1")

    assert duplicate != original
    assert ObanJobs.count!() == 2
  end

  test "a unique insert that races an open transaction is reported as a conflict and lost when that transaction rolls back" do
    test_pid = self()

    racing_transaction =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          {:ok, %Oban.Job{conflict?: false}} = insert_event("evt-1")
          send(test_pid, :inserted)

          receive do
            :rollback -> TestRepo.rollback(:business_rule_failed)
          after
            5_000 -> flunk("the racing transaction did not receive the rollback signal")
          end
        end)
      end)

    receive do
      :inserted -> :ok
    after
      5_000 -> flunk("the racing transaction did not insert in time")
    end

    assert {:ok, {:ok, %Oban.Job{id: nil, conflict?: true}}} = TestRepo.transaction(fn -> insert_event("evt-1") end)

    send(racing_transaction.pid, :rollback)
    assert {:error, :business_rule_failed} = Task.await(racing_transaction, 5_000)

    assert ObanJobs.count!() == 0
  end
end
