defmodule Trogon.Outbox.ObanPro.DbOutageCrashesQueueTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.TestRepo
  alias Trogon.Outbox.ObanPro.Workers.SlowWorker

  @queue_opts [limit: 2, refresh_interval: 150, xact_retry: 1, xact_delay: 10]

  setup do
    Jobs.truncate!()
    :ok
  end

  defp start_with_statement_timeout!(prefix) do
    key = System.unique_integer([:positive])
    connection = :"#{prefix}_connection_#{key}"

    {:ok, connection_pid} = TestRepo.start_link(name: connection, pool_size: 1)
    on_exit(fn -> stop_quietly(connection_pid) end)

    previous = TestRepo.put_dynamic_repo(connection)
    TestRepo.query!("SET statement_timeout = '150'")
    TestRepo.put_dynamic_repo(previous)

    {_pid, name} =
      ObanInstance.start!(
        name: :"#{prefix}_#{key}",
        get_dynamic_repo: fn -> connection end,
        queues: [slow: @queue_opts]
      )

    {key, name}
  end

  @tag :pro_behavior_changed
  test "a producer refresh cancelled by statement_timeout under lock contention crashes the queue and kills the running job" do
    {key, name} = start_with_statement_timeout!(:db_outage)

    {:ok, job} = Oban.insert(name, SlowWorker.new(%{"key" => key, "sleep_ms" => 5_000}))

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 end)
    assert Jobs.state(job.id) == "executing"

    producer = Oban.Registry.whereis(name, {:producer, "slow"})
    assert is_pid(producer)

    %{running: running} = :sys.get_state(producer)
    [{task, _executor}] = Map.values(running)
    assert Process.alive?(task)

    task_ref = Process.monitor(task)
    producer_ref = Process.monitor(producer)

    test_pid = self()
    release_ref = make_ref()

    lock_holder =
      Task.async(fn ->
        TestRepo.transaction(
          fn ->
            TestRepo.query!("LOCK TABLE public.oban_producers IN ACCESS EXCLUSIVE MODE")
            send(test_pid, {:locked, release_ref})

            receive do
              {:release, ^release_ref} -> :ok
            after
              5_000 -> :ok
            end
          end,
          timeout: :infinity
        )
      end)

    assert_receive {:locked, ^release_ref}, 1_000
    assert_receive {:DOWN, ^producer_ref, :process, ^producer, _reason}, 3_000
    assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 3_000

    send(lock_holder.pid, {:release, release_ref})
    Task.await(lock_holder, 5_000)

    assert Counter.get({:finished, key}) == 0
    assert Jobs.state(job.id) == "executing"
  end

  test "a lock held for less than statement_timeout leaves the producer running and the job completes" do
    {key, name} = start_with_statement_timeout!(:db_blip)

    {:ok, job} = Oban.insert(name, SlowWorker.new(%{"key" => key, "sleep_ms" => 1_000}))

    Jobs.wait_until(fn -> Counter.get({:started, key}) == 1 end)

    producer = Oban.Registry.whereis(name, {:producer, "slow"})
    assert is_pid(producer)
    producer_ref = Process.monitor(producer)

    TestRepo.transaction(fn ->
      TestRepo.query!("LOCK TABLE public.oban_producers IN ACCESS EXCLUSIVE MODE")
      Process.sleep(50)
    end)

    refute_receive {:DOWN, ^producer_ref, :process, ^producer, _reason}, 1_000
    assert Process.alive?(producer)

    Jobs.wait_until(fn -> Counter.get({:finished, key}) == 1 end, 3_000)
    Jobs.wait_until(fn -> Jobs.state(job.id) == "completed" end)
  end

  defp stop_quietly(pid) do
    GenServer.stop(pid)
  catch
    :exit, _reason -> :ok
  end
end
