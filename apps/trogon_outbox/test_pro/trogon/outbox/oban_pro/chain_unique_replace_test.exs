defmodule Trogon.Outbox.ObanPro.ChainUniqueReplaceWorker do
  @moduledoc false
  use Oban.Pro.Worker,
    queue: :chain_unique_replace,
    max_attempts: 1,
    chain: [by: [args: [:key]]],
    unique: [period: 300, keys: [:key, :op], states: [:available, :scheduled, :suspended, :executing]]

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Pro.Worker
  def process(%Oban.Job{args: %{"key" => key, "op" => op} = args}) do
    Counter.bump({:ran, key, op})
    order = Counter.bump({:chain_order_seq, key})
    Counter.max_update({:order_for, key, op}, order)
    Counter.max_update({:val_seen, key, op}, Map.get(args, "val", 0))
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.ChainUniqueReplaceTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.ChainUniqueReplaceWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  setup do
    Jobs.truncate!()
    :ok
  end

  test "replace updates the held chain link's args in place, with no new row, and the chain still releases it before a later unrelated chain job" do
    key = System.unique_integer([:positive])
    {_pid, inserter} = ObanInstance.start!(name: :"chain_unique_replace_ins_#{key}", queues: [])

    {:ok, head} = Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "head"}))
    assert Jobs.state(head.id) == "available"

    {:ok, original} = Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "b", "val" => 1}))
    assert Jobs.state(original.id) == "suspended"

    {:ok, unrelated} = Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "c", "val" => 1}))
    assert Jobs.state(unrelated.id) == "suspended"

    {:ok, replaced} =
      Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "b", "val" => 2}, replace: [suspended: [:args]]))

    assert replaced.conflict?
    assert replaced.id == original.id
    assert row_count(key, "b") == 1

    {_pid, runner} =
      ObanInstance.start!(name: :"chain_unique_replace_run_#{key}", queues: [chain_unique_replace: 5])

    :ok = ObanInstance.await_producer!(runner, :chain_unique_replace)

    Jobs.wait_until(fn -> Jobs.state(unrelated.id) == "completed" end, 10_000)

    assert Counter.get({:order_for, key, "head"}) < Counter.get({:order_for, key, "b"})
    assert Counter.get({:order_for, key, "b"}) < Counter.get({:order_for, key, "c"})
    assert Counter.get({:val_seen, key, "b"}) == 2
    assert row_count(key, "b") == 1
  end

  test "replace is a no-op outside the states named in its own per-state key list, so stale args ship when the chain releases the held job" do
    key = System.unique_integer([:positive])
    {_pid, inserter} = ObanInstance.start!(name: :"chain_unique_replace_noop_ins_#{key}", queues: [])

    {:ok, head} = Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "head"}))
    assert Jobs.state(head.id) == "available"

    {:ok, original} = Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "b", "val" => 1}))
    assert Jobs.state(original.id) == "suspended"

    {:ok, replaced} =
      Oban.insert(inserter, Worker.new(%{"key" => key, "op" => "b", "val" => 2}, replace: [available: [:args]]))

    assert replaced.conflict?
    assert replaced.id == original.id
    assert row_count(key, "b") == 1

    {_pid, runner} =
      ObanInstance.start!(name: :"chain_unique_replace_noop_run_#{key}", queues: [chain_unique_replace: 5])

    :ok = ObanInstance.await_producer!(runner, :chain_unique_replace)

    Jobs.wait_until(fn -> Jobs.state(original.id) == "completed" end, 10_000)

    assert Counter.get({:val_seen, key, "b"}) == 1
    assert row_count(key, "b") == 1
  end

  defp row_count(key, op) do
    %Postgrex.Result{rows: [[count]]} =
      TestRepo.query!(
        "SELECT count(*) FROM public.oban_jobs WHERE args ->> 'key' = $1 AND args ->> 'op' = $2",
        [to_string(key), op]
      )

    count
  end
end
