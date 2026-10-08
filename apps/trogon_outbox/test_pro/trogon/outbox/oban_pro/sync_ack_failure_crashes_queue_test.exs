defmodule Trogon.Outbox.ObanPro.SyncAckFailureCrashesQueueTest do
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

  defp start_sync_ack!(prefix, setting) do
    key = System.unique_integer([:positive])
    connection = :"#{prefix}_connection_#{key}"

    {:ok, connection_pid} =
      TestRepo.start_link(name: connection, pool_size: 2, after_connect: {Postgrex, :query!, [setting, []]})

    on_exit(fn -> stop_quietly(connection_pid) end)

    {_pid, name} =
      ObanInstance.start!(
        name: :"#{prefix}_#{key}",
        get_dynamic_repo: fn -> connection end,
        # The limit matches the two jobs the test runs, so the producer never starts a fetch while
        # the table is locked. A fetch retries lock errors forever and would never reach the ack.
        queues: [slow: [limit: 2, ack_async: false, xact_retry: 1, xact_delay: 10]]
      )

    {key, name}
  end

  # Holds the lock until told to release it, rather than for a fixed duration, so the
  # test does not have to guess how long the ack attempt it is racing against will take
  # to arrive under load. assert_receive on the caller side bounds the total wait.
  defp hold_jobs_lock! do
    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(
          fn ->
            TestRepo.query!("LOCK TABLE public.oban_jobs IN EXCLUSIVE MODE")
            send(test_pid, :jobs_locked)

            receive do
              :release -> :ok
            after
              60_000 -> :ok
            end
          end,
          timeout: :infinity
        )
      end)

    assert_receive :jobs_locked, 1_000
    holder
  end

  test "with ack_async: false, a completion ack that fails on lock_timeout crashes the queue and kills an unrelated running job" do
    {key, name} = start_sync_ack!(:sync_ack_lock_timeout, "SET lock_timeout = '150'")

    {:ok, long} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-long", "sleep_ms" => 120_000}))
    {:ok, short} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-short", "sleep_ms" => 5_000}))

    Jobs.wait_until(
      fn -> Counter.get({:started, "#{key}-long"}) == 1 and Counter.get({:started, "#{key}-short"}) == 1 end,
      15_000
    )

    producer = Oban.Registry.whereis(name, {:producer, "slow"})
    %{running: running} = :sys.get_state(producer)
    long_task = Enum.find_value(Map.values(running), fn {task, executor} -> executor.job.id == long.id && task end)

    producer_ref = Process.monitor(producer)
    task_ref = Process.monitor(long_task)

    holder = hold_jobs_lock!()

    assert_receive {:DOWN, ^producer_ref, :process, ^producer, reason}, 60_000
    assert {{:badmatch, {:error, %Postgrex.Error{postgres: %{code: :lock_not_available}}}}, _stack} = reason
    assert_receive {:DOWN, ^task_ref, :process, ^long_task, _reason}, 1_000
    assert Counter.get({:finished, "#{key}-short"}) == 1

    send(holder.pid, :release)
    Task.await(holder, 5_000)

    {:ok, after_lock} = Oban.insert(name, SlowWorker.new(%{"key" => "#{key}-after", "sleep_ms" => 10}))
    Jobs.wait_until(fn -> Jobs.state(after_lock.id) == "completed" end, 10_000)
    Jobs.wait_until(fn -> Jobs.state(short.id) == "completed" end, 10_000)

    Process.sleep(10_000)

    assert Counter.get({:finished, "#{key}-long"}) == 0
    assert Jobs.state(long.id) == "executing"
  end

  defp stop_quietly(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end
