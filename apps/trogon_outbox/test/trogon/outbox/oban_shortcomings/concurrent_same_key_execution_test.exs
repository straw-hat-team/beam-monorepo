defmodule Trogon.Outbox.ObanShortcomings.ConcurrentSameKeyExecutionTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule BlockingWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:started, id, job.attempted_by})

      receive do
        :release -> :ok
      after
        5_000 -> {:error, :not_released}
      end
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "two nodes with a limit of 1 each run two jobs for the same source at the same time" do
    for {name, node} <- [{:concurrent_node_a, "node-a"}, {:concurrent_node_b, "node-b"}] do
      start_supervised!({Oban, ObanInstance.opts(name, node: node, queues: [relay: 1])})
    end

    reply_to = ObanReply.encode(self())

    for sequence <- [1, 2] do
      %{"source" => "order-1", "sequence" => sequence, "reply_to" => reply_to}
      |> BlockingWorker.new()
      |> then(&Oban.insert!(:concurrent_node_a, &1))
    end

    started =
      for _job <- [1, 2] do
        receive do
          {:started, id, [node | _]} -> {id, node}
        after
          5_000 -> flunk("both same-source jobs did not start while the other was still running")
        end
      end

    assert started |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [1, 2]
    assert started |> Enum.map(&elem(&1, 1)) |> Enum.sort() == ["node-a", "node-b"]
    assert ObanJobs.state!(1) == "executing"
    assert ObanJobs.state!(2) == "executing"
  end
end
