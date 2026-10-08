defmodule Trogon.Outbox.ObanPro.LifelineRequiresLeadershipTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  defmodule IdleWorker do
    @moduledoc false
    use Oban.Worker, queue: :lifeline_leadership, max_attempts: 3

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    Jobs.truncate!()
    :ok
  end

  test "an orphaned job is not rescued while another node without Lifeline holds leadership, and is rescued once it steps down" do
    key = System.unique_integer([:positive])
    name = :"lifeline_leadership_#{key}"

    TestRepo.query!(
      """
      INSERT INTO public.oban_peers (name, node, started_at, expires_at)
      VALUES ($1, 'node-without-pro-lifeline', now() at time zone 'utc', (now() at time zone 'utc') + interval '1 hour')
      """,
      [inspect(name)]
    )

    {_pid, ^name} = ObanInstance.start!(name: name, queues: [], lifeline: {Oban.Pro.Lifeline, rescue_interval: 200})

    plugins = Enum.map(Oban.config(name).plugins, fn {module, _opts} -> module end)
    assert Oban.Pro.Lifeline in plugins

    job = insert_orphan!(name)

    Process.sleep(1_500)

    refute Oban.Peer.leader?(name)
    assert Jobs.state(job.id) == "executing"

    TestRepo.query!("DELETE FROM public.oban_peers WHERE name = $1", [inspect(name)])
    Oban.Notifier.notify(name, :leader, %{down: inspect(name)})

    Jobs.wait_until(fn -> Oban.Peer.leader?(name) end, 5_000)
    Jobs.wait_until(fn -> Jobs.state(job.id) == "available" end, 5_000)
  end

  defp insert_orphan!(name) do
    {:ok, job} = Oban.insert(name, IdleWorker.new(%{}))

    TestRepo.query!(
      """
      UPDATE public.oban_jobs
      SET state = 'executing', attempt = 1, attempted_at = now() at time zone 'utc',
          attempted_by = ARRAY['gone-node', gen_random_uuid()::text]
      WHERE id = $1
      """,
      [job.id]
    )

    job
  end
end
