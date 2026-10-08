defmodule Trogon.Outbox.ObanPro.AsyncAckLossDuplicateTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a completion ack lost before it reaches the database, followed by the producer vanishing, runs the job twice" do
    key = System.unique_integer([:positive])
    name = :"async_ack_loss_#{key}"

    {node_a, ^name} = ObanInstance.start!(name: name, queues: [])
    {:ok, job} = Oban.insert(name, CounterWorker.new(%{"key" => key}, max_attempts: 2))

    drop_pending_ack_on_stop(name, job.id)

    :ok = ObanInstance.await_notifier!(name)
    :ok = Oban.start_queue(name, queue: :counter, limit: 5)

    Jobs.wait_until(fn -> Counter.get(key) == 1 end)
    Process.sleep(300)

    assert Jobs.state(job.id) == "executing"
    assert Counter.get(key) == 1

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    {_pid, node_b} =
      ObanInstance.start!(
        name: :"async_ack_loss_node_b_#{key}",
        queues: [counter: 5],
        plugins: [{Oban.Pro.Plugins.DynamicLifeline, rescue_interval: 200}]
      )

    Jobs.wait_until(fn -> Counter.get(key) == 2 end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
    assert Oban.Peer.leader?(node_b)
  end

  defp drop_pending_ack_on_stop(name, job_id) do
    handler_id = "async-ack-loss-#{job_id}"

    :telemetry.attach(
      handler_id,
      [:oban, :job, :stop],
      fn _event, _measurements, %{job: %{id: id, queue: queue}}, _config ->
        if id == job_id do
          :ets.delete(:"pro_ack_tab_#{:erlang.phash2(queue, 8)}", {:ack, to_string(name), queue, id})
          :telemetry.detach(handler_id)
        end
      end,
      nil
    )
  end
end
