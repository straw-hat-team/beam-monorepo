defmodule Trogon.Outbox.ObanPro.DefaultConfigRunsNoLifelineTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule IdleWorker do
    @moduledoc false
    use Oban.Worker, queue: :default_lifeline, max_attempts: 3

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  test "a Pro engine instance started without a lifeline option runs no lifeline, so an orphaned job stays executing" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"default_lifeline_#{key}", queues: [default_lifeline: 1])

    plugins = Enum.map(Oban.config(name).plugins, fn {module, _opts} -> module end)
    refute Oban.Pro.Lifeline in plugins
    refute Oban.Pro.Plugins.DynamicLifeline in plugins
    refute Oban.Lifeline in plugins

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end, 5_000)

    {:ok, job} = Oban.insert(name, IdleWorker.new(%{}, schedule_in: 3_600))

    TestRepo.query!(
      """
      UPDATE public.oban_jobs
      SET state = 'executing', attempt = 1, attempted_at = (now() at time zone 'utc') - interval '2 hours',
          attempted_by = ARRAY['gone-node', gen_random_uuid()::text]
      WHERE id = $1
      """,
      [job.id]
    )

    Process.sleep(2_000)

    assert Jobs.state(job.id) == "executing"
  end
end
