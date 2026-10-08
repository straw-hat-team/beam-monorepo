defmodule Trogon.Outbox.ObanPro.RateLimitProducerRestartBurstWorker do
  @moduledoc false
  use Oban.Worker, queue: :rate_restart, max_attempts: 1

  alias Trogon.Outbox.ObanPro.Counter

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}) do
    Counter.bump({:completed, key})
    :ok
  end
end

defmodule Trogon.Outbox.ObanPro.RateLimitProducerRestartBurstTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.ObanPro.Counter
  alias Trogon.Outbox.ObanPro.Jobs
  alias Trogon.Outbox.ObanPro.ObanInstance
  alias Trogon.Outbox.ObanPro.RateLimitProducerRestartBurstWorker, as: Worker

  @allowed 5
  @period 6
  @queue_opts [limit: 50, rate_limit: [allowed: @allowed, period: @period]]

  setup do
    Jobs.truncate!()
    :ok
  end

  test "without a restart, a burst of supply does not let the queue complete more than allowed within one period" do
    key = System.unique_integer([:positive])
    window_opened_no_earlier_than = System.monotonic_time(:millisecond)
    {_pid, name} = ObanInstance.start!(name: :"rate_restart_control_#{key}", queues: [rate_restart: @queue_opts])
    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :rate_restart)

    insert_jobs!(name, key, 20)

    Jobs.wait_until(fn -> Counter.get({:completed, key}) == @allowed end, 5_000)
    sample_at = window_opened_no_earlier_than + @period * 1_000 - 1_500
    Process.sleep(max(sample_at - System.monotonic_time(:millisecond), 0))

    assert Counter.get({:completed, key}) == @allowed
  end

  test "a bare process restart keeps the old producer row around, so its merged window still throttles the fresh producer" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"rate_restart_stale_row_#{key}", queues: [rate_restart: @queue_opts])
    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :rate_restart)

    insert_jobs!(name, key, @allowed)

    Jobs.wait_until(fn -> Counter.get({:completed, key}) == @allowed end, 5_000)

    :ok = Oban.stop_queue(name, queue: :rate_restart)
    :ok = Oban.start_queue(name, queue: :rate_restart, limit: 50, rate_limit: [allowed: @allowed, period: @period])
    :ok = ObanInstance.await_producer!(name, :rate_restart)

    insert_jobs!(name, key, @allowed)

    assert_raise ExUnit.AssertionError, ~r/timed out/, fn ->
      Jobs.wait_until(fn -> Counter.get({:completed, key}) > @allowed end, 3_000)
    end

    assert Counter.get({:completed, key}) == @allowed
  end

  test "deleting the producer row before the restart drops its merged window, so the fresh producer opens a full new allowance mid period" do
    key = System.unique_integer([:positive])
    {_pid, name} = ObanInstance.start!(name: :"rate_restart_row_loss_#{key}", queues: [rate_restart: @queue_opts])
    :ok = ObanInstance.await_notifier!(name)
    :ok = ObanInstance.await_producer!(name, :rate_restart)

    insert_jobs!(name, key, @allowed)

    Jobs.wait_until(fn -> Counter.get({:completed, key}) == @allowed end, 5_000)

    :ok = Oban.stop_queue(name, queue: :rate_restart)
    Jobs.delete_producers!(name)
    :ok = Oban.start_queue(name, queue: :rate_restart, limit: 50, rate_limit: [allowed: @allowed, period: @period])
    :ok = ObanInstance.await_producer!(name, :rate_restart)

    insert_jobs!(name, key, @allowed)

    Jobs.wait_until(fn -> Counter.get({:completed, key}) > @allowed end, 5_000)
  end

  defp insert_jobs!(name, key, count) do
    for _job <- 1..count do
      {:ok, _job} = Oban.insert(name, Worker.new(%{"key" => key}))
    end
  end
end
