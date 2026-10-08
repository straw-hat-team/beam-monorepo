defmodule Trogon.Outbox.ObanPro.AckAsyncFalseNoDuplicateTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.Workers.CounterWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  test "with ack_async: false a completed job is not run again after its producer vanishes" do
    key = System.unique_integer([:positive])
    name = :"ack_sync_#{key}"

    {node_a, ^name} = ObanInstance.start!(name: name, queues: [counter: [limit: 5, ack_async: false]])
    {:ok, job} = Oban.insert(name, CounterWorker.new(%{"key" => key}, max_attempts: 2))

    drop_pending_ack_on_stop(name, job.id)

    Jobs.wait_until(fn -> Counter.get(key) == 1 end)
    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
    assert Counter.get(key) == 1

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    {_pid, node_b} =
      ObanInstance.start!(
        name: :"ack_sync_node_b_#{key}",
        queues: [counter: [limit: 5, ack_async: false]],
        plugins: [{Oban.Pro.Plugins.DynamicLifeline, rescue_interval: 200}]
      )

    Process.sleep(1_000)

    assert Counter.get(key) == 1
    assert Jobs.state(job.id) == "completed"
    assert Oban.Peer.leader?(node_b)
  end

  defp drop_pending_ack_on_stop(name, job_id) do
    handler_id = "ack-sync-#{job_id}"

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
