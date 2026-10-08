defmodule Trogon.Outbox.ObanPro.ChunkCrashDuplicatesEntireChunkTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChunkCrashWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a crash in the middle of a chunk retries and republishes every job in the chunk" do
    key = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(name: :"chunk_crash_#{key}", queues: [chunk_crash: 1], stage_interval: 100)

    jobs =
      for seq <- 1..3 do
        {:ok, job} = Oban.insert(name, ChunkCrashWorker.new(%{"key" => key, "seq" => seq}))
        job
      end

    for %{id: id} <- jobs, do: Jobs.wait_until(fn -> Jobs.state(id) == "completed" end, 10_000)

    for seq <- 1..3 do
      assert Counter.get({:published, key, seq}) == 2
    end
  end
end
