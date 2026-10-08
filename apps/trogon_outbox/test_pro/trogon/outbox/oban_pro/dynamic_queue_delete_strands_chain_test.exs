defmodule Trogon.Outbox.ObanPro.DynamicQueueDeleteStrandsChainTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule DynChainWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :dyn_relay, max_attempts: 1, chain: [by: [args: [:key]]]

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key, "seq" => seq}}) do
      Counter.bump({:order, key, seq}, Counter.bump({:finished, key}))
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    TestRepo.query!("DELETE FROM public.oban_queues")
    on_exit(fn -> TestRepo.query!("DELETE FROM public.oban_queues") end)
    :ok
  end

  defp producers(queue) do
    %Postgrex.Result{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM public.oban_producers WHERE queue = $1", [to_string(queue)])

    count
  end

  test "deleting a dynamic queue stops it on every node and leaves its chain jobs waiting with no error until the queue is inserted again" do
    key = System.unique_integer([:positive])
    queues = {Oban.Pro.Queues, queues: [dyn_relay: 2]}

    {_a, name_a} = ObanInstance.start!(name: :"dyn_relay_a_#{key}", queues: queues)
    {_b, name_b} = ObanInstance.start!(name: :"dyn_relay_b_#{key}", queues: queues)
    Jobs.wait_until(fn -> producers(:dyn_relay) == 2 end, 10_000)
    :ok = ObanInstance.await_notifier!(name_a)
    :ok = ObanInstance.await_notifier!(name_b)

    {:ok, _queue} = Oban.Pro.Queues.delete(name_a, :dyn_relay)

    Jobs.wait_until(
      fn ->
        is_nil(Oban.Registry.whereis(name_a, {:supervisor, "dyn_relay"})) and
          is_nil(Oban.Registry.whereis(name_b, {:supervisor, "dyn_relay"}))
      end,
      10_000
    )

    jobs =
      for seq <- 1..3 do
        {:ok, job} = Oban.insert(name_a, DynChainWorker.new(%{"key" => key, "seq" => seq}))
        job
      end

    Process.sleep(2_000)

    assert Enum.map(jobs, &Jobs.state(&1.id)) == ["available", "suspended", "suspended"]

    assert Enum.all?(
             jobs,
             &(TestRepo.query!("SELECT errors FROM public.oban_jobs WHERE id = $1", [&1.id]).rows == [[[]]])
           )

    assert Counter.get({:finished, key}) == 0

    {:ok, _queues} = Oban.Pro.Queues.insert(name_a, dyn_relay: 2)

    Jobs.wait_until(fn -> Enum.all?(jobs, &(Jobs.state(&1.id) == "completed")) end, 15_000)
    assert Enum.map(1..3, &Counter.get({:order, key, &1})) == [1, 2, 3]
  end
end
