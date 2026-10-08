defmodule Trogon.Outbox.ObanShortcomings.TestingModesHideRelayFailuresTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"event_id" => event_id}} = job) do
      ObanReply.send(job, {:started, event_id})
      Process.sleep(200)
      ObanReply.send(job, {:finished, event_id})
      :ok
    end
  end

  defmodule UniquePublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp new_event(event_id), do: PublishWorker.new(%{"event_id" => event_id, "reply_to" => ObanReply.encode(self())})

  test "with testing: :inline a job inserted in a transaction that then rolls back has already published" do
    start_supervised!({Oban, ObanInstance.opts(:inline_relay, testing: :inline)})

    assert {:error, :business_write_failed} =
             TestRepo.transaction(fn ->
               Oban.insert!(:inline_relay, new_event("evt-1"))
               TestRepo.rollback(:business_write_failed)
             end)

    assert_received {:finished, "evt-1"}
    assert ObanJobs.count!() == 0
  end

  defp lock_key!(name, event_id) do
    {:error, [lock_key]} =
      TestRepo.transaction(fn ->
        {:ok, %Oban.Job{}} = Oban.insert(name, UniquePublishWorker.new(%{"event_id" => event_id}))

        TestRepo
        |> SQL.query!(
          "SELECT (classid::bigint << 32) | objid::bigint FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
        )
        |> Map.fetch!(:rows)
        |> List.flatten()
        |> TestRepo.rollback()
      end)

    lock_key
  end

  defp hold_advisory_lock!(lock_key) do
    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          SQL.query!(TestRepo, "SELECT pg_advisory_xact_lock($1)", [lock_key])
          send(test_pid, :holding)

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the lock holder did not receive the release signal")
          end
        end)
      end)

    assert_receive :holding, 5_000
    holder
  end

  test "with testing: :manual a unique insert is stored while its advisory lock key is held, where a running instance drops it" do
    start_supervised!({Oban, ObanInstance.opts(:running_relay)})
    start_supervised!({Oban, ObanInstance.opts(:manual_relay, testing: :manual)})

    event = %{"event_id" => "evt-1"}
    holder = hold_advisory_lock!(lock_key!(:running_relay, "evt-1"))

    assert {:ok, %Oban.Job{id: nil, conflict?: true}} = Oban.insert(:running_relay, UniquePublishWorker.new(event))
    assert ObanJobs.count!() == 0

    assert {:ok, %Oban.Job{id: id, conflict?: false}} = Oban.insert(:manual_relay, UniquePublishWorker.new(event))
    assert is_integer(id)
    assert ObanJobs.count!() == 1

    send(holder.pid, :release)
    Task.await(holder, 5_000)
  end

  defp publish_timeline(job_count) do
    for _step <- 1..(job_count * 2) do
      receive do
        {step, event_id} when step in [:started, :finished] -> {step, event_id}
      after
        5_000 -> flunk("a job never reported its next step")
      end
    end
  end

  test "drain_queue runs jobs one at a time in insert order, so jobs a queue with a limit of 2 would overlap never do" do
    start_supervised!({Oban, ObanInstance.opts(:drained_relay, testing: :manual)})

    Oban.insert!(:drained_relay, new_event("evt-1"))
    Oban.insert!(:drained_relay, new_event("evt-2"))

    assert %{success: 2} = Oban.drain_queue(:drained_relay, queue: :relay)

    assert publish_timeline(2) == [
             {:started, "evt-1"},
             {:finished, "evt-1"},
             {:started, "evt-2"},
             {:finished, "evt-2"}
           ]
  end

  test "the same jobs on a running queue with a limit of 2 overlap" do
    start_supervised!({Oban, ObanInstance.opts(:running_relay, queues: [relay: [limit: 2, paused: true]])})
    :ok = ObanInstance.await_notifier!(:running_relay)

    Oban.insert!(:running_relay, new_event("evt-1"))
    Oban.insert!(:running_relay, new_event("evt-2"))
    :ok = Oban.resume_queue(:running_relay, queue: :relay)

    assert [{:started, _first}, {:started, _second} | _finishes] = publish_timeline(2)
  end
end
