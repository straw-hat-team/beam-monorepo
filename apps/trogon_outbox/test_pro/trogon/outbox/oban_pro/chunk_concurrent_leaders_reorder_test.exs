defmodule Trogon.Outbox.ObanPro.ChunkConcurrentLeadersReorderTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChunkOrderWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "two chunks for the same key running concurrently can complete out of enqueue order" do
    key = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(name: :"chunk_order_#{key}", queues: [chunk_order: 2], stage_interval: 100)

    _jobs = Oban.insert_all(name, for(seq <- 1..4, do: ChunkOrderWorker.new(%{"key" => key, "seq" => seq})))

    for seq <- 1..4 do
      Jobs.wait_until(fn -> Counter.get({:completed_order, key, seq}) > 0 end, 10_000)
    end

    order_of = fn seq -> Counter.get({:completed_order, key, seq}) end

    assert order_of.(2) < order_of.(1), "completion order: #{inspect(Enum.map(1..4, &{&1, order_of.(&1)}))}"
  end
end
