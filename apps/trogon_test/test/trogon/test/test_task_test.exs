defmodule Trogon.Test.TestTaskTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockDateTime
  alias Trogon.Test.MockTask

  describe "stub/1" do
    test "runs the function in a real task" do
      test = self()

      result =
        Task.await(
          MockTask.async(fn ->
            send(test, :ran)
            :real
          end)
        )

      assert result == :real
      assert_received :ran
    end

    test "awaits the real task" do
      result = MockTask.await(Task.async(fn -> :real end), 1_000)

      assert result == :real
    end

    test "streams the function in real tasks" do
      results = Enum.to_list(MockTask.async_stream([1, 2], &(&1 * 10), []))

      assert results == [ok: 10, ok: 20]
    end
  end

  describe "expect_async/1" do
    test "runs the function in a real task owned by the caller" do
      test = self()
      TestTask.expect_async(times: 1)

      task =
        MockTask.async(fn ->
          send(test, :ran)
          :real
        end)

      assert %Task{owner: ^test} = task
      assert Task.await(task) == :real
      assert_received :ran
      Trogon.Test.assert_empty_mailbox()
    end

    test "runs the function with the caller in its $callers, so the mocks it calls reach the test" do
      TestTask.expect_async(times: 1)
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      now = Task.await(MockTask.async(&MockDateTime.utc_now/0))

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestTask.expect_async()

      Task.await(MockTask.async(fn -> :ran end))

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.async(fn -> :ran end) end
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestTask.expect_async(times: 2)

      results = Task.await_many([MockTask.async(fn -> :first end), MockTask.async(fn -> :second end)])

      assert results == [:first, :second]
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_await/1" do
    test "awaits the real task and records the timeout" do
      TestTask.expect_await(times: 1)

      result = MockTask.await(Task.async(fn -> :real end), 1_000)

      assert result == :real
      TestTask.assert_received_await(1_000)
      Trogon.Test.assert_empty_mailbox()
    end

    @tag :capture_log
    test "exits as Task.await/2 does when the task exits" do
      TestTask.expect_await(times: 1)
      Process.flag(:trap_exit, true)
      task = Task.async(fn -> exit(:boom) end)

      assert catch_exit(MockTask.await(task, 1_000)) == {:boom, {Task, :await, [task, 1_000]}}
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestTask.expect_await()
      MockTask.await(Task.async(fn -> :ran end), :infinity)

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.await(Task.async(fn -> :ran end), :infinity) end
      TestTask.assert_received_await(:infinity)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_await_timeout/1" do
    test "exits as Task.await/2 does after the timeout, without waiting for it" do
      TestTask.expect_await_timeout(times: 1)
      task = Task.async(fn -> :ran end)

      reason = catch_exit(MockTask.await(task, 60_000))

      assert reason == {:timeout, {Task, :await, [task, 60_000]}}
      TestTask.assert_received_await(60_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "exits with the reason a real timeout gives" do
      TestTask.expect_await_timeout(times: 1)
      slow = Task.async(fn -> Process.sleep(:infinity) end)
      task = Task.async(fn -> :ran end)

      real = catch_exit(Task.await(slow, 0))
      mocked = catch_exit(MockTask.await(task, 0))

      assert mocked == put_elem(real, 1, {Task, :await, [task, 0]})
      TestTask.assert_received_await(0)
      Trogon.Test.assert_empty_mailbox()
    end

    test "drops the reply the task sends afterwards, as a real timeout does" do
      TestTask.expect_await_timeout(times: 1)
      test = self()

      task =
        Task.async(fn ->
          receive do
            :reply -> send(test, :replied)
          end

          :late
        end)

      catch_exit(MockTask.await(task, 0))
      send(task.pid, :reply)

      assert_receive :replied
      ref = Process.monitor(task.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}
      refute_received {_ref, :late}
      TestTask.assert_received_await(0)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects :infinity, which never times out" do
      TestTask.expect_await_timeout(times: 1)
      task = Task.async(fn -> :ran end)

      assert_raise ArgumentError, ~r/:infinity/, fn -> MockTask.await(task, :infinity) end
      assert Task.await(task) == :ran
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a task the caller does not own, as Task.await/2 does" do
      TestTask.expect_await_timeout(times: 1)
      task = Task.async(fn -> :ran end)

      {real, mocked} =
        Task.await(Task.async(fn -> {catch_error(Task.await(task, 0)), catch_error(MockTask.await(task, 0))} end))

      assert %ArgumentError{} = real
      assert mocked == real
      assert Task.await(task) == :ran
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_async_stream/1" do
    test "streams the function in real tasks and records the options" do
      TestTask.expect_async_stream(times: 1)

      results = Enum.to_list(MockTask.async_stream([1, 2], &(&1 * 10), max_concurrency: 2))

      assert results == [ok: 10, ok: 20]
      TestTask.assert_received_async_stream(max_concurrency: 2)
      Trogon.Test.assert_empty_mailbox()
    end

    test "runs the function with the caller in its $callers, so the mocks it calls reach the test" do
      TestTask.expect_async_stream(times: 1)
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      results = Enum.to_list(MockTask.async_stream([:now], fn _item -> MockDateTime.utc_now() end, []))

      assert results == [ok: ~U[2026-01-01 00:00:00.000000Z]]
      TestTask.assert_received_async_stream([])
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestTask.expect_async_stream()

      MockTask.async_stream([], & &1, [])

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.async_stream([], & &1, []) end
      TestTask.assert_received_async_stream([])
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestTask.expect_async_stream(times: 2)

      MockTask.async_stream([], & &1, ordered: true)
      MockTask.async_stream([], & &1, ordered: false)

      TestTask.assert_received_async_stream(ordered: true)
      TestTask.assert_received_async_stream(ordered: false)
      Trogon.Test.assert_empty_mailbox()
    end

    test "fails the assertion on other options" do
      TestTask.expect_async_stream(times: 1)

      MockTask.async_stream([], & &1, max_concurrency: 2)

      assert_raise ExUnit.AssertionError, fn -> TestTask.assert_received_async_stream(max_concurrency: 4) end
      TestTask.assert_received_async_stream(max_concurrency: 2)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "Task contract" do
    test "rejects a function with arguments, as Task.async/1 does" do
      TestTask.expect_async(times: 2)

      assert_raise FunctionClauseError, fn -> Task.async(fn _arg -> :ran end) end
      assert_raise FunctionClauseError, fn -> MockTask.async(fn _arg -> :ran end) end
      assert_raise FunctionClauseError, fn -> MockTask.async(:not_a_function) end
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a timeout that is neither a non-negative integer nor :infinity, as Task.await/2 does" do
      TestTask.expect_await(times: 1)
      TestTask.expect_await_timeout(times: 1)
      task = Task.async(fn -> :ran end)

      assert_raise FunctionClauseError, fn -> Task.await(task, Enum.random([-1])) end
      assert_raise FunctionClauseError, fn -> MockTask.await(task, -1) end
      assert_raise FunctionClauseError, fn -> MockTask.await(task, 1.5) end
      assert Task.await(task) == :ran
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects something other than a task, as Task.await/2 does" do
      TestTask.expect_await(times: 1)

      assert_raise FunctionClauseError, fn -> Task.await(Enum.random([:task]), 0) end
      assert_raise FunctionClauseError, fn -> MockTask.await(:task, 0) end
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a function that does not take one argument, as Task.async_stream/3 does" do
      TestTask.expect_async_stream(times: 1)

      assert_raise FunctionClauseError, fn -> Task.async_stream([], fn -> :ran end, []) end
      assert_raise FunctionClauseError, fn -> MockTask.async_stream([], fn -> :ran end, []) end
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects options that are not a list, as Task.async_stream/3 does" do
      TestTask.expect_async_stream(times: 1)

      assert_raise FunctionClauseError, fn -> Task.async_stream([], & &1, %{ordered: true}) end
      assert_raise FunctionClauseError, fn -> MockTask.async_stream([], & &1, %{ordered: true}) end
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "recording" do
    test "leaves nothing in the mailbox to assert on" do
      TestTask.expect_async(times: 1)

      Task.await(MockTask.async(fn -> :ran end))

      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestTask.expect_async(times: 1)

      result = Task.await(Task.async(fn -> Task.await(MockTask.async(fn -> :ran end)) end))

      assert result == :ran
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
