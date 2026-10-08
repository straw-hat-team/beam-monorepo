defmodule Trogon.Outbox.ObanShortcomings.FailingFetchKillsRunningJobsTest do
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
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id, self()})

      receive do
        :ack -> :ok
      after
        30_000 -> :ok
      end
    end
  end

  setup do
    ObanJobs.truncate!()
    on_exit(&drop_fetch_failure!/0)
    :ok
  end

  defp fail_every_fetch! do
    SQL.query!(TestRepo, """
    CREATE OR REPLACE FUNCTION oss_gaps_fail_fetch() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'fetch unavailable';
    END
    $$ LANGUAGE plpgsql
    """)

    SQL.query!(TestRepo, """
    CREATE TRIGGER oss_gaps_fail_fetch BEFORE UPDATE ON oban_jobs
    FOR EACH ROW WHEN (NEW.state = 'executing') EXECUTE FUNCTION oss_gaps_fail_fetch()
    """)
  end

  defp drop_fetch_failure! do
    SQL.query!(TestRepo, "DROP TRIGGER IF EXISTS oss_gaps_fail_fetch ON oban_jobs")
    SQL.query!(TestRepo, "DROP FUNCTION IF EXISTS oss_gaps_fail_fetch()")
  end

  defp insert_event!(name, sequence) do
    %{"source" => "order-#{sequence}", "reply_to" => ObanReply.encode(self())}
    |> PublishWorker.new()
    |> then(&Oban.insert!(name, &1))
  end

  test "a fetch that keeps failing crashes the producer and kills a job that had already published, leaving it executing" do
    start_supervised!({Oban, ObanInstance.opts(:failing_fetch, queues: [relay: 2])})

    %Oban.Job{id: running} = insert_event!(:failing_fetch, 1)
    assert_receive {:published, ^running, worker}, 5_000
    worker_ref = Process.monitor(worker)

    fail_every_fetch!()
    %Oban.Job{id: next} = insert_event!(:failing_fetch, 2)

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 15_000

    drop_fetch_failure!()

    assert_receive {:published, ^next, _worker}, 15_000
    assert ObanJobs.state!(running) == "executing"
    refute_received {:published, ^running, _worker}
  end
end
