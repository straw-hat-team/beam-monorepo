defmodule Trogon.Test.TestRandTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockRand

  describe "stub/1" do
    test "draws from the real :rand" do
      draws = for _draw <- 1..100, do: MockRand.uniform(3)

      assert Enum.all?(draws, &(&1 in 1..3))
    end
  end

  describe "expect_uniform/1" do
    test "returns the expected number" do
      TestRand.expect_uniform(times: 1, returns: 2)

      result = MockRand.uniform(3)

      assert result == 2
      TestRand.assert_received_uniform(3)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestRand.expect_uniform(returns: 1)
      MockRand.uniform(1)

      assert_raise Mox.UnexpectedCallError, fn -> MockRand.uniform(1) end
      TestRand.assert_received_uniform(1)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestRand.expect_uniform(times: 2, returns: 1)

      results = [MockRand.uniform(2), MockRand.uniform(3)]

      assert results == [1, 1]
      TestRand.assert_received_uniform(2)
      TestRand.assert_received_uniform(3)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestRand.expect_uniform(times: 1, returns: 1)
      MockRand.uniform(1)

      assert_raise Mox.UnexpectedCallError, fn -> MockRand.uniform(1) end
      TestRand.assert_received_uniform(1)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe ":rand contract" do
    test "rejects an n below 1, as :rand.uniform/1 does" do
      TestRand.expect_uniform(times: 1, returns: 1)

      assert_raise FunctionClauseError, fn -> :rand.uniform(0) end
      assert_raise FunctionClauseError, fn -> MockRand.uniform(0) end
    end

    test "rejects an n that is not an integer, as :rand.uniform/1 does" do
      TestRand.expect_uniform(times: 1, returns: 1)

      assert_raise FunctionClauseError, fn -> :rand.uniform(Enum.random([1.5])) end
      assert_raise FunctionClauseError, fn -> MockRand.uniform(Enum.random([1.5])) end
    end

    test "rejects returns: above the n a call was given, which :rand.uniform/1 never returns" do
      TestRand.expect_uniform(times: 1, returns: 4)

      assert :rand.uniform(3) <= 3
      assert_raise ArgumentError, ~r/at most 3/, fn -> MockRand.uniform(3) end
    end

    test "rejects returns: other than a positive integer, which :rand.uniform/1 never returns" do
      for value <- [0, -1, 1.0, :one] do
        assert_raise ArgumentError, fn -> TestRand.expect_uniform(times: 1, returns: value) end
      end
    end
  end

  describe "returns" do
    test "is required" do
      assert_raise KeyError, fn -> TestRand.expect_uniform(times: 1) end
    end
  end

  describe "assert_received_uniform/1" do
    test "fails on a call given another n" do
      TestRand.expect_uniform(times: 1, returns: 1)
      MockRand.uniform(3)

      assert_raise ExUnit.AssertionError, fn -> TestRand.assert_received_uniform(4) end
      TestRand.assert_received_uniform(3)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestRand.expect_uniform(times: 1, returns: 2)

      result = Task.await(Task.async(fn -> MockRand.uniform(3) end))

      assert result == 2
      TestRand.assert_received_uniform(3)
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
