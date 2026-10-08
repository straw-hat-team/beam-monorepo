defmodule Trogon.Outbox.ObanShortcomings.LifelineRescuesOrphanedExecutingJobTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule ChainedWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, attempt: attempt, args: %{"source" => source}} = job) do
      if predecessor_pending?(source, id) do
        ObanReply.send(job, {:waiting, id})
        {:snooze, 0}
      else
        ObanReply.send(job, {:started, id, attempt, self()})
        hang_on_first_attempt(job)
      end
    end

    defp hang_on_first_attempt(%Oban.Job{attempt: 1, args: %{"hang_on_first_attempt" => true}}) do
      receive do
        :never_sent -> :ok
      after
        10_000 -> :ok
      end
    end

    defp hang_on_first_attempt(_job), do: :ok

    defp predecessor_pending?(source, id) do
      %Postgrex.Result{num_rows: num_rows} =
        SQL.query!(
          TestRepo,
          "SELECT id FROM oban_jobs WHERE args->>'source' = $1 AND id < $2 AND state != 'completed' LIMIT 1",
          [source, id]
        )

      num_rows > 0
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp orphan_head_job!(name) do
    start_supervised!({Oban, ObanInstance.opts(name, node: "node-a", queues: [relay: 1])})

    %Oban.Job{id: id} =
      %{"source" => "order-1", "hang_on_first_attempt" => true, "reply_to" => ObanReply.encode(self())}
      |> ChainedWorker.new()
      |> then(&Oban.insert!(name, &1))

    assert_receive {:started, ^id, 1, _pid}, 5_000
    :ok = stop_supervised(name)
    assert ObanJobs.state!(id) == "executing"

    id
  end

  defp insert_successor!(name) do
    %Oban.Job{id: id} =
      %{"source" => "order-1", "reply_to" => ObanReply.encode(self())}
      |> ChainedWorker.new()
      |> then(&Oban.insert!(name, &1))

    id
  end

  test "without Lifeline an orphaned executing job is never picked up again and its successor waits behind it" do
    head = orphan_head_job!(:no_lifeline_node_a)

    start_supervised!({Oban, ObanInstance.opts(:no_lifeline_node_b, node: "node-b", queues: [relay: 2])})
    successor = insert_successor!(:no_lifeline_node_b)

    for _check <- 1..5 do
      assert_receive {:waiting, ^successor}, 5_000
    end

    refute_received {:started, ^head, _attempt, _pid}
    assert ObanJobs.state!(head) == "executing"
    assert ObanJobs.fetch(head).attempted_by |> hd() == "node-a"
  end

  test "Lifeline moves an orphaned executing job back to available after rescue_after and its successor then proceeds" do
    head = orphan_head_job!(:lifeline_node_a)

    start_supervised!(
      {Oban,
       ObanInstance.opts(:lifeline_node_b,
         node: "node-b",
         queues: [relay: 2],
         lifeline: [rescue_after: 500, interval: 50]
       )}
    )

    successor = insert_successor!(:lifeline_node_b)

    {head_rescue_attempts, successor_attempt} = await_head_rescues_then_successor(head, successor)

    assert hd(head_rescue_attempts) == 2
    assert successor_attempt == 1
    assert ObanJobs.eventually(fn -> ObanJobs.state!(successor) == "completed" end)
  end

  # rescue_after: 500 is tight enough that the head's own completion write after being rescued
  # to attempt 2 can occasionally land more than 500ms after it started under load, so Lifeline
  # legitimately rescues it again before it completes (the same live-job double-rescue the third
  # test in this file proves). The successor can only start once the head is actually
  # "completed", so it always starts after the head's last restart; collecting every head
  # restart until the successor starts keeps the assertion deterministic without hiding extra
  # rescues or weakening the point that Lifeline's first rescue lands at attempt 2.
  defp await_head_rescues_then_successor(head, successor, head_rescue_attempts \\ []) do
    receive do
      {:started, ^head, attempt, _pid} ->
        await_head_rescues_then_successor(head, successor, [attempt | head_rescue_attempts])

      {:started, ^successor, attempt, _pid} ->
        {Enum.reverse(head_rescue_attempts), attempt}
    after
      5_000 -> flunk("the rescued head and its successor did not both start in time")
    end
  end

  test "Lifeline also rescues a job that is still genuinely executing, so it runs twice at the same time" do
    start_supervised!(
      {Oban,
       ObanInstance.opts(:lifeline_live_job,
         queues: [relay: 2],
         lifeline: [rescue_after: 100, interval: 50]
       )}
    )

    %Oban.Job{id: id} =
      %{"source" => "order-1", "hang_on_first_attempt" => true, "reply_to" => ObanReply.encode(self())}
      |> ChainedWorker.new()
      |> then(&Oban.insert!(:lifeline_live_job, &1))

    assert_receive {:started, ^id, 1, first_run}, 5_000
    assert_receive {:started, ^id, 2, second_run}, 5_000

    assert first_run != second_run
    assert Process.alive?(first_run)
  end
end
