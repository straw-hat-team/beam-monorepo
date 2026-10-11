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
