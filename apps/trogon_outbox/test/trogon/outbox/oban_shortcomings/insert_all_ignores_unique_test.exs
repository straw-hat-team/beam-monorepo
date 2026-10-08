defmodule Trogon.Outbox.ObanShortcomings.InsertAllIgnoresUniqueTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.Jobs
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    Jobs.truncate!()
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(:insert_all_node)})
    :ok
  end

  test "Oban.insert/2 rejects a unique duplicate but Oban.insert_all/2 inserts the same duplicate anyway" do
    {:ok, %Oban.Job{conflict?: false}} = Oban.insert(:insert_all_node, PublishWorker.new(%{"event_id" => "evt-1"}))

    changesets = [PublishWorker.new(%{"event_id" => "evt-1"}), PublishWorker.new(%{"event_id" => "evt-1"})]
    jobs = Oban.insert_all(:insert_all_node, changesets)

    assert length(jobs) == 2
    assert ObanJobs.count!() == 3
  end

  test "insert_all inside the business transaction is atomic even though it ignores uniqueness" do
    assert {:error, :business_rule_failed} =
             TestRepo.transaction(fn ->
               Jobs.insert!("order-1", "pending")
               changesets = [PublishWorker.new(%{"event_id" => "evt-2"}), PublishWorker.new(%{"event_id" => "evt-2"})]
               Oban.insert_all(:insert_all_node, changesets)
               TestRepo.rollback(:business_rule_failed)
             end)

    assert TestRepo.aggregate("outbox_jobs", :count) == 0
    assert ObanJobs.count!() == 0
  end
end
