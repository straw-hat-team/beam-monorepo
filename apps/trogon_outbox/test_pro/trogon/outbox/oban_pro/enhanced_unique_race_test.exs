defmodule Trogon.Outbox.ObanPro.EnhancedUniqueRaceTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.UniqueWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "with the unique index migrated, 20 concurrent inserts for one unique key create exactly one row" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"enhanced_unique_#{key}", queues: [])

    tasks =
      for _insert <- 1..20 do
        Task.async(fn ->
          receive do
            :go -> Oban.insert(name, UniqueWorker.new(%{"key" => key}))
          end
        end)
      end

    for %Task{pid: pid} <- tasks, do: send(pid, :go)

    assert tasks |> Task.await_many(10_000) |> Enum.all?(&match?({:ok, _job}, &1))
    assert Jobs.count_by_key(key) == 1
  end
end
