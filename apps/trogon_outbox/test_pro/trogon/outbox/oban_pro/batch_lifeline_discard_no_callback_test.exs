defmodule Trogon.Outbox.ObanPro.BatchLifelineDiscardNoCallbackTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule BatchWorker do
    @moduledoc false
    use Oban.Pro.Worker, queue: :batch_lifeline, max_attempts: 1

    @behaviour Oban.Pro.Batch

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Pro.Worker
    def process(%Oban.Job{args: %{"key" => key, "mode" => "slow"}}) do
      Counter.bump({:started, key})
      Process.sleep(5_000)
      :ok
    end

    def process(%Oban.Job{args: %{"mode" => "discard"}}), do: {:discard, "boom"}

    def process(%Oban.Job{args: %{"key" => key}}) do
      Counter.bump({:ran, key})
      :ok
    end

    @impl Oban.Pro.Batch
    def batch_discarded(%Oban.Job{meta: %{"batch_id" => batch_id}}) do
      Counter.bump({:discarded_callback, batch_id})
      :ok
    end

    @impl Oban.Pro.Batch
    def batch_exhausted(%Oban.Job{meta: %{"batch_id" => batch_id}}) do
      Counter.bump({:exhausted_callback, batch_id})
      :ok
    end
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  defp insert_batch!(name, key, last_mode) do
    batch_id = "batch-lifeline-#{key}"

    jobs =
      [%{"key" => key, "mode" => "ok"}, %{"key" => key, "mode" => last_mode}]
      |> Enum.map(&BatchWorker.new/1)
      |> Oban.Pro.Batch.new(batch_id: batch_id)
      |> then(&Oban.insert_all(name, &1))

    {batch_id, jobs}
  end

  defp callback_jobs(batch_id) do
    %Postgrex.Result{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM public.oban_jobs WHERE meta ->> 'batch_id' = $1 AND meta ? 'callback'", [
        batch_id
      ])

    count
  end

  test "a batch whose last job is discarded by Lifeline after a node death never gets its discarded or exhausted callback" do
    key = System.unique_integer([:positive])
    name = :"batch_lifeline_dead_#{key}"

    {node_a, ^name} = ObanInstance.start!(name: name, queues: [batch_lifeline: 2], shutdown_grace_period: 10)

    {batch_id, [ok, slow]} = insert_batch!(name, key, "slow")

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 and Jobs.state(ok.id) == "completed" end)

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    ObanInstance.start!(
      name: :"batch_lifeline_rescuer_#{key}",
      queues: [batch_lifeline: 2],
      lifeline: {Oban.Pro.Lifeline, rescue_interval: 200}
    )

    Jobs.wait_until(fn -> Jobs.state(slow.id) == "discarded" end, 10_000)
    Process.sleep(3_000)

    assert callback_jobs(batch_id) == 0
    assert Counter.get({:discarded_callback, batch_id}) == 0
    assert Counter.get({:exhausted_callback, batch_id}) == 0
  end

  test "a batch whose last job discards itself gets both its discarded and exhausted callbacks" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"batch_lifeline_live_#{key}", queues: [batch_lifeline: 2])

    {batch_id, [_ok, discard]} = insert_batch!(name, key, "discard")

    Jobs.wait_until(fn -> Jobs.state(discard.id) == "discarded" end, 10_000)

    Jobs.wait_until(
      fn -> Counter.get({:discarded_callback, batch_id}) == 1 and Counter.get({:exhausted_callback, batch_id}) == 1 end,
      10_000
    )

    assert callback_jobs(batch_id) == 2
  end
end
