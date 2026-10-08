defmodule Trogon.Outbox.ObanShortcomings.RuntimeQueueChangesLostOnRestartTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  @name :runtime_queue_node

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp start_node!(queue_opts) do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: queue_opts])})
    :ok = ObanInstance.await_notifier!(@name)
  end

  defp restart_node!(queue_opts) do
    :ok = stop_supervised(@name)
    start_node!(queue_opts)
  end

  test "a queue paused at runtime publishes again as soon as its node restarts" do
    start_node!(limit: 1)

    assert :ok = Oban.pause_queue(@name, queue: :relay)
    assert ObanJobs.eventually(fn -> Oban.check_queue(@name, queue: :relay).paused end)

    %Oban.Job{id: id} = Oban.insert!(@name, PublishWorker.new(%{"reply_to" => ObanReply.encode(self())}))
    refute_receive {:published, ^id}, 500

    restart_node!(limit: 1)

    refute Oban.check_queue(@name, queue: :relay).paused
    assert_receive {:published, ^id}, 5_000
  end

  test "a queue scaled down at runtime comes back at its configured limit after its node restarts" do
    start_node!(limit: 5)

    assert :ok = Oban.scale_queue(@name, queue: :relay, limit: 1)
    assert ObanJobs.eventually(fn -> Oban.check_queue(@name, queue: :relay).limit == 1 end)

    restart_node!(limit: 5)

    assert Oban.check_queue(@name, queue: :relay).limit == 5
  end
end
