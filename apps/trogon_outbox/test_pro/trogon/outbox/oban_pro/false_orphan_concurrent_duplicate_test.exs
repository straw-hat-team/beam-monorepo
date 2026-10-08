defmodule Trogon.Outbox.ObanPro.FalseOrphanConcurrentDuplicateTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.SlowWorker

  setup do
    Jobs.truncate!()
    :ok
  end

  @tag :pro_behavior_changed
  test "a stalled producer whose row is evicted by a healthy peer runs its still-executing job a second time concurrently" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"false_orphan_#{key}", queues: [slow: [limit: 2, refresh_interval: 100]])
    conf = Oban.config(name)

    {:ok, job} = Oban.insert(name, SlowWorker.new(%{"key" => key, "sleep_ms" => 4_000}))

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 end)
    assert Jobs.state(job.id) == "executing"

    producer = Oban.Registry.whereis(name, {:producer, "slow"})
    assert is_pid(producer)
    on_exit(fn -> resume_quietly(producer) end)

    :sys.suspend(producer)
    Process.sleep(600)

    assert Counter.get({:started, key}) == 1
    assert Counter.get({:finished, key}) == 0

    healthy_peer =
      Oban.Repo.insert!(
        conf,
        Oban.Pro.Producer.new(
          name: conf.name,
          node: "healthy-peer",
          queue: "slow",
          refresh_interval: 100,
          meta: %{},
          started_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        )
      )

    Oban.Pro.Engine.refresh(conf, healthy_peer)

    assert TestRepo.query!("SELECT count(*) FROM public.oban_producers WHERE queue = 'slow'").rows == [[1]]
    assert Counter.get({:finished, key}) == 0
    assert Jobs.state(job.id) == "executing"

    lifeline = ObanInstance.start_plugin!(Oban.Pro.Plugins.DynamicLifeline, name, rescue_interval: 150)

    Jobs.wait_until(fn -> Jobs.state(job.id) == "available" end, 5_000)

    assert Counter.get({:started, key}) == 1
    assert Counter.get({:finished, key}) == 0

    GenServer.stop(lifeline)

    send(producer, {:notification, :insert, %{"queue" => "slow"}})
    :sys.resume(producer)

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 2 end, 2_000)
    assert Counter.get({:finished, key}) == 0

    Jobs.wait_until(fn -> Counter.get({:finished, key}) == 2 end, 5_000)
  end

  defp resume_quietly(pid) do
    :sys.resume(pid)
  catch
    :exit, _reason -> :ok
  end
end
