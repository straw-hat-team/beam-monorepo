defmodule Trogon.Outbox.ObanPro.InsertAllAppliesUniquenessTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.UniqueWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "insert_all stores one row for duplicate unique keys within a call and across calls" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"insert_all_unique_#{key}", queues: [])

    assert [_job] = Oban.insert_all(name, for(_job <- 1..5, do: UniqueWorker.new(%{"key" => key})))
    assert Jobs.count_by_key(key) == 1

    assert [_job] = Oban.insert_all(name, [UniqueWorker.new(%{"key" => key})])
    assert Jobs.count_by_key(key) == 1
  end
end
