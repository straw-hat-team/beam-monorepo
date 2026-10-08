defmodule Trogon.Outbox.ObanPro.CronDuplicateInstanceTickWorker do
  @moduledoc false
  use Oban.Worker, queue: :cron_tick, max_attempts: 1

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Trogon.Outbox.ObanPro.CronDuplicateInstanceTickUniqueWorker do
  @moduledoc false
  use Oban.Worker, queue: :cron_tick_unique, max_attempts: 1, unique: [period: 60, keys: [:key]]

  @impl Oban.Worker
  def perform(_job), do: :ok
end

defmodule Trogon.Outbox.ObanPro.CronDuplicateInstanceTickTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.CronDuplicateInstanceTickUniqueWorker, as: UniqueWorker
  alias Trogon.Outbox.ObanPro.CronDuplicateInstanceTickWorker, as: Worker
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo

  setup do
    Jobs.truncate!()
    :ok
  end

  test "two differently-named leader instances sharing a crontab and database each independently tick and insert their own row for the same logical minute" do
    key = System.unique_integer([:positive])
    crontab = [{"* * * * *", Worker, args: %{"key" => key}, name: "tick-#{key}"}]

    {_pid_a, name_a} = ObanInstance.start!(name: :"cron_dup_a_#{key}", queues: [])
    {_pid_b, name_b} = ObanInstance.start!(name: :"cron_dup_b_#{key}", queues: [])

    plugin_a = ObanInstance.start_plugin!(Oban.Pro.Cron, name_a, crontab: crontab)
    plugin_b = ObanInstance.start_plugin!(Oban.Pro.Cron, name_b, crontab: crontab)

    assert Oban.Peer.leader?(name_a)
    assert Oban.Peer.leader?(name_b)

    send(plugin_a, :evaluate)
    send(plugin_b, :evaluate)

    Jobs.wait_until(fn -> row_count(key, "cron_tick") == 2 end, 5_000)
  end

  test "the same two-instance setup with the cron worker declaring unique: results in only one row for the logical minute" do
    key = System.unique_integer([:positive])
    crontab = [{"* * * * *", UniqueWorker, args: %{"key" => key}, name: "tick-unique-#{key}"}]

    {_pid_a, name_a} = ObanInstance.start!(name: :"cron_dup_unique_a_#{key}", queues: [])
    {_pid_b, name_b} = ObanInstance.start!(name: :"cron_dup_unique_b_#{key}", queues: [])

    plugin_a = ObanInstance.start_plugin!(Oban.Pro.Cron, name_a, crontab: crontab)
    plugin_b = ObanInstance.start_plugin!(Oban.Pro.Cron, name_b, crontab: crontab)

    send(plugin_a, :evaluate)
    send(plugin_b, :evaluate)

    Jobs.wait_until(fn -> row_count(key, "cron_tick_unique") == 1 end, 5_000)

    Process.sleep(300)
    assert row_count(key, "cron_tick_unique") == 1
  end

  test "GenServer.call(pid, :evaluate) runs manage_entries and reload_and_insert even on a plugin instance that is not the Peer leader" do
    key = System.unique_integer([:positive])
    name = :"cron_dup_nonleader_#{key}"

    TestRepo.query!(
      """
      INSERT INTO public.oban_peers (name, node, started_at, expires_at)
      VALUES ($1, 'node-without-this-cron-plugin', now() at time zone 'utc', (now() at time zone 'utc') + interval '1 hour')
      """,
      [inspect(name)]
    )

    {_pid, ^name} = ObanInstance.start!(name: name, queues: [])
    refute Oban.Peer.leader?(name)

    crontab = [{"* * * * *", Worker, args: %{"key" => key}, name: "tick-nonleader-#{key}"}]
    plugin = ObanInstance.start_plugin!(Oban.Pro.Cron, name, crontab: crontab)

    send(plugin, :evaluate)
    Process.sleep(300)
    assert row_count(key, "cron_tick") == 0

    :ok = GenServer.call(plugin, :evaluate)
    assert row_count(key, "cron_tick") == 1
  end

  defp row_count(key, queue) do
    %Postgrex.Result{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM public.oban_jobs WHERE args ->> 'key' = $1 AND queue = $2", [
        to_string(key),
        queue
      ])

    count
  end
end
