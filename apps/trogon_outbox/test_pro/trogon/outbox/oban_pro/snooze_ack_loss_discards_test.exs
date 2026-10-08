defmodule Trogon.Outbox.ObanPro.SnoozeAckLossDiscardsTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance

  defmodule SnoozeWorker do
    @moduledoc false
    use Oban.Worker, queue: :snooze_ack_loss, max_attempts: 1

    alias Trogon.Outbox.ObanPro.Counter

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"key" => key}}) do
      Counter.bump({:ran, key})
      {:snooze, 60}
    end
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a snoozed job keeps its attempt budget when the snooze is recorded" do
    key = System.unique_integer([:positive])
    {_pid, name} = start_node!(:"snooze_ack_kept_#{key}")

    {:ok, job} = Oban.insert(name, SnoozeWorker.new(%{"key" => key}))

    Jobs.wait_until(fn -> Jobs.state(job.id) == "scheduled" end)

    assert %{attempt: 0, max_attempts: 1} = Oban.Repo.get(Oban.config(name), Oban.Job, job.id)
  end

  test "a snoozing job on a node that dies before recording the snooze is discarded by Lifeline without running again" do
    key = System.unique_integer([:positive])
    name = :"snooze_ack_lost_#{key}"
    {node_a, ^name} = start_node!(name)

    drop_pending_ack_on_stop(name)

    {:ok, job} = Oban.insert(name, SnoozeWorker.new(%{"key" => key}))

    Jobs.wait_until(fn -> Counter.get({:ran, key}) == 1 end)
    Process.sleep(300)
    assert Jobs.state(job.id) == "executing"

    Supervisor.stop(node_a)
    Jobs.delete_producers!(name)

    ObanInstance.start!(
      name: :"snooze_ack_lost_rescuer_#{key}",
      queues: [snooze_ack_loss: 1],
      lifeline: {Oban.Pro.Lifeline, rescue_interval: 200}
    )

    Jobs.wait_until(fn -> Jobs.state(job.id) == "discarded" end, 10_000)
    Process.sleep(500)

    assert Counter.get({:ran, key}) == 1
  end

  defp start_node!(name) do
    result = ObanInstance.start!(name: name, queues: [snooze_ack_loss: 1])
    :ok = ObanInstance.await_producer!(name, :snooze_ack_loss)
    result
  end

  defp drop_pending_ack_on_stop(name) do
    handler_id = "snooze-ack-loss-#{name}"

    :telemetry.attach(
      handler_id,
      [:oban, :job, :stop],
      fn _event, _measurements, %{conf: conf, job: %{id: id, queue: queue}}, _config ->
        if conf.name == name do
          :ets.delete(:"pro_ack_tab_#{:erlang.phash2(queue, 8)}", {:ack, to_string(name), queue, id})
          :telemetry.detach(handler_id)
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
