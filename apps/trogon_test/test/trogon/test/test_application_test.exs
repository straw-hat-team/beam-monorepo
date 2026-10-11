defmodule Trogon.Test.TestApplicationTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockApplication

  describe "stub/1" do
    test "reads a configured key from the real Application env" do
      value = MockApplication.get_env(:trogon_test, :seeded_value, nil)

      assert value == "real value"
    end

    test "fetches a configured key from the real Application env" do
      result = MockApplication.fetch_env(:trogon_test, :seeded_value)

      assert result == {:ok, "real value"}
    end

    test "fetches a configured key with fetch_env!/2 from the real Application env" do
      value = MockApplication.fetch_env!(:trogon_test, :seeded_value)

      assert value == "real value"
    end

    test "reads every key of the real Application env" do
      env = MockApplication.get_all_env(:trogon_test)

      assert Enum.sort(env) == Enum.sort(Application.get_all_env(:trogon_test))
    end
  end

  describe "expect_get_env/1" do
    test "returns the expected value" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      value = MockApplication.get_env(:trogon_test, :seeded_value, :default)

      assert value == "overridden"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value, :default)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestApplication.expect_get_env(times: 2, returns: "overridden")

      values = [MockApplication.get_env(:trogon_test, :first, nil), MockApplication.get_env(:trogon_test, :second, nil)]

      assert values == ["overridden", "overridden"]
      TestApplication.assert_received_get_env(:trogon_test, :first)
      TestApplication.assert_received_get_env(:trogon_test, :second)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      assert_raise Mox.UnexpectedCallError, fn -> MockApplication.get_env(:trogon_test, :seeded_value, nil) end
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end

    test "leaves the real Application env untouched" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      value = Application.get_env(:trogon_test, :seeded_value)

      assert value == "real value"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_fetch_env/1" do
    test "returns the expected result" do
      TestApplication.expect_fetch_env(times: 1, returns: :error)

      result = MockApplication.fetch_env(:trogon_test, :seeded_value)

      assert result == :error
      TestApplication.assert_received_fetch_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_fetch_env/1 with a value" do
    test "returns the expected value" do
      TestApplication.expect_fetch_env(times: 1, returns: {:ok, "overridden"})

      result = MockApplication.fetch_env(:trogon_test, :seeded_value)

      assert result == {:ok, "overridden"}
      TestApplication.assert_received_fetch_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_fetch_env!/1" do
    test "returns the expected value" do
      TestApplication.expect_fetch_env!(times: 1, returns: "overridden")

      value = MockApplication.fetch_env!(:trogon_test, :seeded_value)

      assert value == "overridden"
      TestApplication.assert_received_fetch_env!(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_get_all_env/1" do
    test "returns the expected env" do
      TestApplication.expect_get_all_env(times: 1, returns: [seeded_value: "overridden"])

      env = MockApplication.get_all_env(:trogon_test)

      assert env == [seeded_value: "overridden"]
      TestApplication.assert_received_get_all_env(:trogon_test)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "times" do
    test "covers as many fetch_env/2 calls as times, and rejects one past it" do
      TestApplication.expect_fetch_env(times: 2, returns: :error)

      MockApplication.fetch_env(:trogon_test, :first)
      MockApplication.fetch_env(:trogon_test, :second)

      assert_raise Mox.UnexpectedCallError, fn -> MockApplication.fetch_env(:trogon_test, :third) end
      TestApplication.assert_received_fetch_env(:trogon_test, :first)
      TestApplication.assert_received_fetch_env(:trogon_test, :second)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many fetch_env!/2 calls as times, and rejects one past it" do
      TestApplication.expect_fetch_env!(times: 2, returns: "overridden")

      MockApplication.fetch_env!(:trogon_test, :first)
      MockApplication.fetch_env!(:trogon_test, :second)

      assert_raise Mox.UnexpectedCallError, fn -> MockApplication.fetch_env!(:trogon_test, :third) end
      TestApplication.assert_received_fetch_env!(:trogon_test, :first)
      TestApplication.assert_received_fetch_env!(:trogon_test, :second)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many get_all_env/1 calls as times, and rejects one past it" do
      TestApplication.expect_get_all_env(times: 2, returns: [])

      MockApplication.get_all_env(:first)
      MockApplication.get_all_env(:second)

      assert_raise Mox.UnexpectedCallError, fn -> MockApplication.get_all_env(:third) end
      TestApplication.assert_received_get_all_env(:first)
      TestApplication.assert_received_get_all_env(:second)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "returns" do
    test "is required by every expectation" do
      assert_raise KeyError, fn -> TestApplication.expect_get_env(times: 1) end
      assert_raise KeyError, fn -> TestApplication.expect_fetch_env(times: 1) end
      assert_raise KeyError, fn -> TestApplication.expect_fetch_env!(times: 1) end
      assert_raise KeyError, fn -> TestApplication.expect_get_all_env(times: 1) end
    end
  end

  describe "assert_received_*" do
    test "fails on a call given other arguments" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      TestApplication.expect_fetch_env(times: 1, returns: :error)
      TestApplication.expect_fetch_env!(times: 1, returns: "overridden")
      TestApplication.expect_get_all_env(times: 1, returns: [])

      MockApplication.get_env(:trogon_test, :seeded_value, :default)
      MockApplication.fetch_env(:trogon_test, :seeded_value)
      MockApplication.fetch_env!(:trogon_test, :seeded_value)
      MockApplication.get_all_env(:trogon_test)

      assert_raise ExUnit.AssertionError, fn -> TestApplication.assert_received_get_env(:trogon_test, :other) end

      assert_raise ExUnit.AssertionError, fn ->
        TestApplication.assert_received_get_env(:trogon_test, :seeded_value, :other)
      end

      assert_raise ExUnit.AssertionError, fn -> TestApplication.assert_received_fetch_env(:trogon_test, :other) end
      assert_raise ExUnit.AssertionError, fn -> TestApplication.assert_received_fetch_env!(:trogon_test, :other) end
      assert_raise ExUnit.AssertionError, fn -> TestApplication.assert_received_get_all_env(:other) end
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value, :default)
      TestApplication.assert_received_fetch_env(:trogon_test, :seeded_value)
      TestApplication.assert_received_fetch_env!(:trogon_test, :seeded_value)
      TestApplication.assert_received_get_all_env(:trogon_test)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "Application contract" do
    test "rejects an app that is not an atom, as Application.get_env/3 does" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      assert_raise FunctionClauseError, fn -> Application.get_env("trogon_test", :seeded_value, nil) end
      assert_raise FunctionClauseError, fn -> MockApplication.get_env("trogon_test", :seeded_value, nil) end
    end

    test "rejects an app that is not an atom, as Application.fetch_env/2 does" do
      TestApplication.expect_fetch_env(times: 1, returns: :error)

      assert_raise FunctionClauseError, fn -> Application.fetch_env("trogon_test", :seeded_value) end
      assert_raise FunctionClauseError, fn -> MockApplication.fetch_env("trogon_test", :seeded_value) end
    end

    test "rejects an app that is not an atom, as Application.fetch_env!/2 does" do
      TestApplication.expect_fetch_env!(times: 1, returns: "overridden")

      assert_raise FunctionClauseError, fn -> Application.fetch_env!("trogon_test", :seeded_value) end
      assert_raise FunctionClauseError, fn -> MockApplication.fetch_env!("trogon_test", :seeded_value) end
    end

    test "rejects an app that is not an atom, as Application.get_all_env/1 does" do
      TestApplication.expect_get_all_env(times: 1, returns: [])

      assert_raise FunctionClauseError, fn -> Application.get_all_env("trogon_test") end
      assert_raise FunctionClauseError, fn -> MockApplication.get_all_env("trogon_test") end
    end

    test "accepts a key that is not an atom, as Application does with a warning" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      TestApplication.expect_fetch_env(times: 1, returns: :error)
      TestApplication.expect_fetch_env!(times: 1, returns: "overridden")

      warnings =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Application.get_env(:trogon_test, "seeded_value")
          Application.fetch_env(:trogon_test, "seeded_value")
          assert_raise ArgumentError, ~r/was not set/, fn -> Application.fetch_env!(:trogon_test, "seeded_value") end
        end)

      assert warnings =~ "seeded_value"
      MockApplication.get_env(:trogon_test, "seeded_value", nil)
      MockApplication.fetch_env(:trogon_test, "seeded_value")
      MockApplication.fetch_env!(:trogon_test, "seeded_value")
      TestApplication.assert_received_get_env(:trogon_test, "seeded_value")
      TestApplication.assert_received_fetch_env(:trogon_test, "seeded_value")
      TestApplication.assert_received_fetch_env!(:trogon_test, "seeded_value")
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects fetch_env/2 returns: other than {:ok, value} or :error, which Application.fetch_env/2 never returns" do
      results = [Application.fetch_env(:trogon_test, :seeded_value), Application.fetch_env(:trogon_test, :missing)]

      assert results == [{:ok, "real value"}, :error]
      assert_raise ArgumentError, fn -> TestApplication.expect_fetch_env(times: 1, returns: "real value") end
    end

    test "rejects get_all_env/1 returns: other than a keyword list, which Application.get_all_env/1 never returns" do
      assert Keyword.keyword?(Application.get_all_env(:trogon_test))

      assert_raise ArgumentError, fn -> TestApplication.expect_get_all_env(times: 1, returns: %{seeded_value: 1}) end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      value = Task.await(Task.async(fn -> MockApplication.get_env(:trogon_test, :seeded_value, nil) end))

      assert value == "overridden"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end

    test "reaches a process allowed with Mox.allow/3" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      parent = self()

      pid =
        spawn(fn ->
          receive do
            :read -> send(parent, {:read, MockApplication.get_env(:trogon_test, :seeded_value, nil)})
          end
        end)

      Mox.allow(MockApplication, self(), pid)

      send(pid, :read)

      assert_receive {:read, "overridden"}
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
