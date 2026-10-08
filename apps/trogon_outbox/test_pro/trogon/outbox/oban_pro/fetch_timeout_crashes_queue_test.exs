defmodule Trogon.Outbox.ObanPro.FetchTimeoutCrashesQueueTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.SlowWorker

  @queue_opts [limit: 3, xact_retry: 1, xact_delay: 10]

  setup do
    Jobs.truncate!()
    :ok
  end

  defp start_with_setting!(prefix, setting) do
    key = System.unique_integer([:positive])
    connection = :"#{prefix}_connection_#{key}"

    {:ok, connection_pid} =
      TestRepo.start_link(name: connection, pool_size: 2, after_connect: {Postgrex, :query!, [setting, []]})

    on_exit(fn -> stop_quietly(connection_pid) end)

    {_pid, name} =
      ObanInstance.start!(
        name: :"#{prefix}_#{key}",
        get_dynamic_repo: fn -> connection end,
        queues: [slow: @queue_opts]
      )

    {key, name}
  end

  defp start_running!(name, key) do
    {:ok, long} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-long", "sleep_ms" => 6_000}))
    {:ok, short} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-short", "sleep_ms" => 1_500}))

    Jobs.wait_until(fn ->
      Counter.get({:started, "#{key}-long"}) == 1 and Counter.get({:started, "#{key}-short"}) == 1
    end)

    Process.sleep(500)

    producer = Oban.Registry.whereis(name, {:producer, "slow"})
    %{running: running} = :sys.get_state(producer)

    long_task = Enum.find_value(Map.values(running), fn {task, executor} -> executor.job.id == long.id && task end)

    %{long: long, short: short, producer: producer, long_task: long_task}
  end

  defp hold_jobs_lock!(duration_ms) do
    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(
          fn ->
            TestRepo.query!("LOCK TABLE public.oban_jobs IN EXCLUSIVE MODE")
            send(test_pid, :jobs_locked)
            Process.sleep(duration_ms)
          end,
          timeout: :infinity
        )
      end)

    assert_receive :jobs_locked, 1_000
    holder
  end

  test "a job fetch cancelled by statement_timeout crashes the queue, kills an unrelated running job, and leaves a finished job executing until the next fetch" do
    {key, name} = start_with_setting!(:fetch_statement_timeout, "SET statement_timeout = '150'")
    %{long: long, short: short, producer: producer, long_task: long_task} = start_running!(name, key)

    assert is_pid(long_task)
    producer_ref = Process.monitor(producer)
    task_ref = Process.monitor(long_task)

    holder = hold_jobs_lock!(2_500)
    refute Counter.get({:finished, "#{key}-short"}) == 1

    assert_receive {:DOWN, ^producer_ref, :process, ^producer, _reason}, 4_000
    assert_receive {:DOWN, ^task_ref, :process, ^long_task, _reason}, 1_000

    Task.await(holder, 5_000)

    Process.sleep(2_000)
    assert Counter.get({:finished, "#{key}-short"}) == 1
    assert Jobs.state(short.id) == "executing"

    {:ok, after_outage} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-after", "sleep_ms" => 10}))
    Jobs.wait_until(fn -> Jobs.state(after_outage.id) == "completed" end, 5_000)
    Jobs.wait_until(fn -> Jobs.state(short.id) == "completed" end, 5_000)

    Process.sleep(6_000)

    assert Counter.get({:finished, "#{key}-long"}) == 0
    assert Jobs.state(long.id) == "executing"
  end

  test "a job fetch blocked past lock_timeout retries without crashing and every running job completes" do
    {key, name} = start_with_setting!(:fetch_lock_timeout, "SET lock_timeout = '150'")
    %{long: long, short: short, producer: producer} = start_running!(name, key)

    producer_ref = Process.monitor(producer)

    holder = hold_jobs_lock!(2_500)

    refute_receive {:DOWN, ^producer_ref, :process, ^producer, _reason}, 3_000
    Task.await(holder, 5_000)

    Jobs.wait_until(fn -> Jobs.state(short.id) == "completed" end, 5_000)
    Jobs.wait_until(fn -> Jobs.state(long.id) == "completed" end, 10_000)

    assert Process.alive?(producer)
    assert Counter.get({:finished, "#{key}-long"}) == 1
  end

  defp stop_quietly(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end
