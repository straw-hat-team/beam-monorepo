defmodule Trogon.Outbox.ObanShortcomings.InsertAllPreservesListOrderTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Trogon.Outbox.TestRepo
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
    start_supervised!({Oban, ObanInstance.opts(:insert_all_order)})
    :ok
  end

  test "insert_all assigns ids and returns jobs in the order of the list it was given" do
    sequences = Enum.shuffle(1..200)

    returned =
      sequences
      |> Enum.map(&PublishWorker.new(%{"sequence" => &1}))
      |> then(&Oban.insert_all(:insert_all_order, &1))

    assert Enum.map(returned, & &1.args["sequence"]) == sequences

    stored =
      Oban.Job
      |> order_by(asc: :id)
      |> select([j], fragment("(?->>'sequence')::int", j.args))
      |> TestRepo.all()

    assert stored == sequences
  end
end
