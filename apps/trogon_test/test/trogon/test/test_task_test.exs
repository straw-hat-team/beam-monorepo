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
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end

    test "runs the function with the caller in its $callers, so the mocks it calls reach the test" do
      TestTask.expect_async(times: 1)
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      now = Task.await(MockTask.async(&MockDateTime.utc_now/0))

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestTask.assert_received_async()
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestTask.expect_async()

      Task.await(MockTask.async(fn -> :ran end))

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.async(fn -> :ran end) end
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestTask.expect_async(times: 2)

      results = Task.await_many([MockTask.async(fn -> :first end), MockTask.async(fn -> :second end)])

      assert results == [:first, :second]
      TestTask.assert_received_async()
      TestTask.assert_received_async()
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
  end

  describe "assert_received_async/0" do
    test "returns the function the call was given" do
      TestTask.expect_async(times: 1)
      fun = fn -> :ran end
      Task.await(MockTask.async(fun))

      assert TestTask.assert_received_async() == fun
      Trogon.Test.assert_empty_mailbox()
    end

    test "fails when no call was made" do
      assert_raise ExUnit.AssertionError, fn -> TestTask.assert_received_async() end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestTask.expect_async(times: 1)

      result = Task.await(Task.async(fn -> Task.await(MockTask.async(fn -> :ran end)) end))

      assert result == :ran
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
