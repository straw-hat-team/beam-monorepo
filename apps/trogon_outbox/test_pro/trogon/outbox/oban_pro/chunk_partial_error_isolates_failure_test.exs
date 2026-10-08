defmodule Trogon.Outbox.ObanPro.ChunkPartialErrorIsolatesFailureTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.ChunkPartialErrorWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a chunk returning {:error, reason, jobs} retries only the listed jobs" do
    key = System.unique_integer([:positive])

    {_pid, name} =
      ObanInstance.start!(name: :"chunk_partial_#{key}", queues: [chunk_partial: 1], stage_interval: 100)

    jobs =
      for {seq, fail} <- [{1, false}, {2, true}, {3, false}] do
        {:ok, job} = Oban.insert(name, ChunkPartialErrorWorker.new(%{"key" => key, "seq" => seq, "fail" => fail}))
        job
      end

    for %{id: id} <- jobs, do: Jobs.wait_until(fn -> Jobs.state(id) == "completed" end, 10_000)

    assert Counter.get({:ran, key, 1}) == 1
    assert Counter.get({:ran, key, 2}) == 2
    assert Counter.get({:ran, key, 3}) == 1
  end
end
