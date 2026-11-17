defmodule Trogon.Test.TestEnumTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockEnum

  describe "stub/1" do
    test "picks with the real Enum.random/1" do
      picks = for _pick <- 1..100, do: MockEnum.random([:a, :b, :c])

      assert Enum.all?(picks, &(&1 in [:a, :b, :c]))
    end
  end

  describe "expect_random/1" do
    test "returns the expected element" do
      TestEnum.expect_random(times: 1, returns: :b)

      result = MockEnum.random([:a, :b, :c])

      assert result == :b
      TestEnum.assert_received_random([:a, :b, :c])
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers one call by default" do
      TestEnum.expect_random(returns: :a)
      MockEnum.random([:a])

      assert_raise Mox.UnexpectedCallError, fn -> MockEnum.random([:a]) end
      TestEnum.assert_received_random([:a])
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestEnum.expect_random(times: 2, returns: 1)

      results = [MockEnum.random([1, 2]), MockEnum.random(1..3)]

      assert results == [1, 1]
      TestEnum.assert_received_random([1, 2])
      TestEnum.assert_received_random(1..3)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestEnum.expect_random(times: 1, returns: :a)
      MockEnum.random([:a])

      assert_raise Mox.UnexpectedCallError, fn -> MockEnum.random([:a]) end
      TestEnum.assert_received_random([:a])
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "Enum.random/1 contract" do
    test "rejects an empty enumerable, as Enum.random/1 does" do
      TestEnum.expect_random(times: 1, returns: :a)

      assert_raise Enum.EmptyError, fn -> Enum.random([]) end
      assert_raise Enum.EmptyError, fn -> MockEnum.random([]) end
    end

    test "rejects a term that is not enumerable, as Enum.random/1 does" do
      TestEnum.expect_random(times: 1, returns: :a)

      assert_raise Protocol.UndefinedError, fn -> Enum.random(Enum.at([:a], 0)) end
      assert_raise Protocol.UndefinedError, fn -> MockEnum.random(Enum.at([:a], 0)) end
    end

    test "rejects returns: outside the enumerable a call was given, which Enum.random/1 never returns" do
      TestEnum.expect_random(times: 1, returns: :z)

      assert Enum.random([:a, :b]) in [:a, :b]
      assert_raise ArgumentError, ~r/element of the enumerable/, fn -> MockEnum.random([:a, :b]) end
    end
  end

  describe "returns" do
    test "is required" do
      assert_raise KeyError, fn -> TestEnum.expect_random(times: 1) end
    end
  end

  describe "assert_received_random/1" do
    test "fails on a call given another enumerable" do
      TestEnum.expect_random(times: 1, returns: :a)
      MockEnum.random([:a, :b])

      assert_raise ExUnit.AssertionError, fn -> TestEnum.assert_received_random([:a]) end
      TestEnum.assert_received_random([:a, :b])
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestEnum.expect_random(times: 1, returns: :b)

      result = Task.await(Task.async(fn -> MockEnum.random([:a, :b]) end))

      assert result == :b
      TestEnum.assert_received_random([:a, :b])
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
