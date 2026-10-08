defmodule Trogon.Outbox.ObanShortcomings.DifferentRepoBreaksAtomicityTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.Jobs
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.SecondRepo

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    Jobs.truncate!()
    ObanJobs.truncate!()
    start_supervised!(SecondRepo)
    start_supervised!({Oban, ObanInstance.opts(:second_repo_node, repo: SecondRepo)})
    :ok
  end

  test "an Oban instance configured with a repo other than the one running the business transaction keeps the job after that transaction rolls back" do
    assert {:error, :business_rule_failed} =
             TestRepo.transaction(fn ->
               Jobs.insert!("order-1", "pending")
               Oban.insert!(:second_repo_node, PublishWorker.new(%{"event_id" => "evt-1"}))
               TestRepo.rollback(:business_rule_failed)
             end)

    assert TestRepo.aggregate("outbox_jobs", :count) == 0
    assert ObanJobs.count!() == 1
  end

  test "the same setup committing the business transaction also keeps both the write and the job" do
    {:ok, %Oban.Job{id: id}} =
      TestRepo.transaction(fn ->
        Jobs.insert!("order-1", "pending")
        Oban.insert!(:second_repo_node, PublishWorker.new(%{"event_id" => "evt-2"}))
      end)

    assert TestRepo.aggregate("outbox_jobs", :count) == 1
    assert ObanJobs.state!(id) == "available"
  end
end
