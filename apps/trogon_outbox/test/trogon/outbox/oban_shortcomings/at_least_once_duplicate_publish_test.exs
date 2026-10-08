defmodule Trogon.Outbox.ObanShortcomings.AtLeastOnceDuplicatePublishTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishThenHangWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, attempt: attempt} = job) do
      ObanReply.send(job, {:published, id, attempt})

      if attempt == 1 do
        receive do
          :never_sent -> :ok
        after
          10_000 -> :ok
        end
      else
        :ok
      end
    end

    @impl Oban.Worker
    def timeout(%Oban.Job{args: %{"timeout_ms" => timeout_ms}}), do: timeout_ms
    def timeout(_job), do: :infinity

    @impl Oban.Worker
    def backoff(_job), do: 0
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a job that published and then timed out is retried and publishes the same event again" do
    start_supervised!({Oban, ObanInstance.opts(:timeout_duplicate, queues: [relay: 1])})

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "timeout_ms" => 100, "reply_to" => ObanReply.encode(self())}
      |> PublishThenHangWorker.new()
      |> then(&Oban.insert!(:timeout_duplicate, &1))

    assert_receive {:published, ^id, 1}, 5_000
    assert_receive {:published, ^id, 2}, 5_000

    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
    assert [%{"error" => error}] = ObanJobs.fetch(id).errors
    assert error =~ "Oban.TimeoutError"
  end

  test "a job that published before its node shut down is left executing and publishes again once rescued" do
    start_supervised!({Oban, ObanInstance.opts(:shutdown_node_a, node: "node-a", queues: [relay: 1])})

    %Oban.Job{id: id} =
      %{"event_id" => "evt-1", "reply_to" => ObanReply.encode(self())}
      |> PublishThenHangWorker.new()
      |> then(&Oban.insert!(:shutdown_node_a, &1))

    assert_receive {:published, ^id, 1}, 5_000

    :ok = stop_supervised(:shutdown_node_a)
    assert ObanJobs.state!(id) == "executing"

    start_supervised!(
      {Oban,
       ObanInstance.opts(:shutdown_node_b,
         node: "node-b",
         queues: [relay: 1],
         lifeline: [rescue_after: 100, interval: 50]
       )}
    )

    assert_receive {:published, ^id, 2}, 5_000
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
  end
end
