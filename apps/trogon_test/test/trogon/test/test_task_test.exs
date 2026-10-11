defmodule Trogon.Test.TestTaskTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockTask

  describe "stub/1" do
    test "runs the function in a real task" do
      test = self()

      result = Task.await(MockTask.async(fn -> send(test, :ran) && :real end))

      assert result == :real
      assert_received :ran
    end
  end

  describe "expect_async/1" do
    test "completes with the expected result without running the function" do
      test = self()
      TestTask.expect_async(times: 1, returns: :expected)

      task = MockTask.async(fn -> send(test, :ran) end)

      assert %Task{owner: ^test} = task
      assert Task.await(task) == :expected
      TestTask.assert_received_async()
      refute_received :ran
      Trogon.Test.assert_empty_mailbox()
    end

    test "completes through Task.yield/2 like a real task" do
      TestTask.expect_async(times: 1, returns: :expected)

      task = MockTask.async(fn -> :ran end)

      assert Task.yield(task, 1_000) == {:ok, :expected}
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestTask.expect_async(returns: :expected)

      Task.await(MockTask.async(fn -> :ran end))

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.async(fn -> :ran end) end
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestTask.expect_async(times: 2, returns: :expected)

      results = Task.await_many([MockTask.async(fn -> :first end), MockTask.async(fn -> :second end)])

      assert results == [:expected, :expected]
      assert TestTask.assert_received_async().() == :first
      assert TestTask.assert_received_async().() == :second
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestTask.expect_async(times: 1, returns: :expected)
      Task.await(MockTask.async(fn -> :ran end))

      assert_raise Mox.UnexpectedCallError, fn -> MockTask.async(fn -> :ran end) end
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "Task contract" do
    test "rejects a function with arguments, as Task.async/1 does" do
      TestTask.expect_async(times: 2, returns: :expected)

      assert_raise FunctionClauseError, fn -> Task.async(fn _arg -> :ran end) end
      assert_raise FunctionClauseError, fn -> MockTask.async(fn _arg -> :ran end) end
      assert_raise FunctionClauseError, fn -> MockTask.async(:not_a_function) end
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "returns" do
    test "is required" do
      assert_raise KeyError, fn -> TestTask.expect_async(times: 1) end
    end
  end

  describe "assert_received_async/0" do
    test "returns the function the call was given" do
      TestTask.expect_async(times: 1, returns: :expected)
      Task.await(MockTask.async(fn -> :ran end))

      fun = TestTask.assert_received_async()

      assert fun.() == :ran
      Trogon.Test.assert_empty_mailbox()
    end

    test "fails when no call was made" do
      assert_raise ExUnit.AssertionError, fn -> TestTask.assert_received_async() end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers, and the task belongs to the caller" do
      TestTask.expect_async(times: 1, returns: :expected)

      result = Task.await(Task.async(fn -> Task.await(MockTask.async(fn -> :ran end)) end))

      assert result == :expected
      TestTask.assert_received_async()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
