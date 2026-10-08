defmodule Trogon.Outbox.ObanShortcomings.KilledJobHasNoStopTelemetryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  @name :killed_job_telemetry_node

  defmodule PublishThenWaitWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, args: args} = job) do
      ObanReply.send(job, {:published, id, self()})

      if args["wait_after_publish"] do
        receive do
          :never_sent -> :ok
        after
          10_000 -> :ok
        end
      end

      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    on_exit(&drop_fetch_failure!/0)
    test_pid = self()
    handler_id = "killed-job-telemetry"

    :telemetry.attach_many(
      handler_id,
      [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception], [:oban, :queue, :shutdown]],
      &__MODULE__.forward_job_event/4,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  def forward_job_event([:oban, :job, event], _measurements, %{conf: %{name: @name}, job: job}, test_pid) do
    send(test_pid, {:job_event, event, job.id})
  end

  def forward_job_event(
        [:oban, :queue, :shutdown],
        _measurements,
        %{conf: %{name: @name}, orphaned: orphaned},
        test_pid
      ) do
    send(test_pid, {:queue_shutdown, orphaned})
  end

  def forward_job_event(_event, _measurements, _metadata, _test_pid), do: :ok

  defp insert_event!(args) do
    args
    |> Map.put("reply_to", ObanReply.encode(self()))
    |> PublishThenWaitWorker.new()
    |> then(&Oban.insert!(@name, &1))
  end

  test "a job killed by a shutdown after it published gets no stop or exception event, only an orphaned entry in the queue shutdown event" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: 1])})

    %Oban.Job{id: id} = insert_event!(%{"event_id" => "evt-1", "wait_after_publish" => true})

    assert_receive {:job_event, :start, ^id}, 5_000
    assert_receive {:published, ^id, _worker}, 5_000

    :ok = stop_supervised(@name)

    assert_receive {:queue_shutdown, [^id]}, 1_000
    refute_receive {:job_event, _event, ^id}, 1_000
    assert ObanJobs.state!(id) == "executing"
  end

  defp fail_every_fetch! do
    SQL.query!(TestRepo, """
    CREATE OR REPLACE FUNCTION killed_job_fail_fetch() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'fetch unavailable';
    END
    $$ LANGUAGE plpgsql
    """)

    SQL.query!(TestRepo, """
    CREATE TRIGGER killed_job_fail_fetch BEFORE UPDATE ON oban_jobs
    FOR EACH ROW WHEN (NEW.state = 'executing') EXECUTE FUNCTION killed_job_fail_fetch()
    """)
  end

  defp drop_fetch_failure! do
    SQL.query!(TestRepo, "DROP TRIGGER IF EXISTS killed_job_fail_fetch ON oban_jobs")
    SQL.query!(TestRepo, "DROP FUNCTION IF EXISTS killed_job_fail_fetch()")
  end

  test "a job killed by a producer crash after it published emits no stop, exception, or queue shutdown event" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: 2])})

    %Oban.Job{id: id} = insert_event!(%{"event_id" => "evt-1", "wait_after_publish" => true})
    assert_receive {:job_event, :start, ^id}, 5_000
    assert_receive {:published, ^id, worker}, 5_000
    worker_ref = Process.monitor(worker)

    fail_every_fetch!()
    insert_event!(%{"event_id" => "evt-2"})

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 15_000
    drop_fetch_failure!()

    refute_receive {:job_event, _event, ^id}, 1_000
    refute_received {:queue_shutdown, _orphaned}
    assert ObanJobs.state!(id) == "executing"
  end

  test "a job that finishes before the shutdown emits its stop event" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [relay: 1])})

    %Oban.Job{id: id} = insert_event!(%{"event_id" => "evt-1"})

    assert_receive {:job_event, :start, ^id}, 5_000
    assert_receive {:job_event, :stop, ^id}, 5_000
    assert ObanJobs.eventually(fn -> ObanJobs.state!(id) == "completed" end)
  end
end
