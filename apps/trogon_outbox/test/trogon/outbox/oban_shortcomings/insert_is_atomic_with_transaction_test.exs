defmodule Trogon.Outbox.ObanShortcomings.InsertIsAtomicWithTransactionTest do
  use ExUnit.Case, async: false

  alias Ecto.Multi
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.Jobs
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    Jobs.truncate!()
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(:atomic_node)})
    :ok
  end

  test "rolling back the business transaction also removes the job inserted inside it" do
    assert {:error, :business_rule_failed} =
             TestRepo.transaction(fn ->
               Jobs.insert!("order-1", "pending")
               Oban.insert!(:atomic_node, PublishWorker.new(%{"event_id" => "evt-1"}))
               TestRepo.rollback(:business_rule_failed)
             end)

    assert TestRepo.aggregate("outbox_jobs", :count) == 0
    assert ObanJobs.count!() == 0
  end

  test "a failing step in an Ecto.Multi also removes the job inserted earlier in it" do
    result =
      Multi.new()
      |> Multi.run(:business_write, fn _repo, _changes -> {:ok, Jobs.insert!("order-1", "pending")} end)
      |> then(&Oban.insert(:atomic_node, &1, :job, PublishWorker.new(%{"event_id" => "evt-1"})))
      |> Multi.run(:business_rule, fn _repo, _changes -> {:error, :business_rule_failed} end)
      |> TestRepo.transaction()

    assert {:error, :business_rule, :business_rule_failed, %{job: %Oban.Job{}}} = result
    assert TestRepo.aggregate("outbox_jobs", :count) == 0
    assert ObanJobs.count!() == 0
  end

  test "committing the business transaction keeps both the write and the job" do
    {:ok, %Oban.Job{id: id}} =
      TestRepo.transaction(fn ->
        Jobs.insert!("order-1", "pending")
        Oban.insert!(:atomic_node, PublishWorker.new(%{"event_id" => "evt-1"}))
      end)

    assert TestRepo.aggregate("outbox_jobs", :count) == 1
    assert ObanJobs.state!(id) == "available"
  end
end
