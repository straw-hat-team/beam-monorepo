defmodule Trogon.Test.TestApplicationTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.TestApplication
  alias Trogon.Test.TestApplication.Mock

  require TestApplication

  setup :verify_on_exit!
  setup {TestApplication, :stub}

  describe "stub/1" do
    test "reads a configured key from the real Application env" do
      value = Mock.get_env(:trogon_test, :seeded_value, nil)

      assert value == "real value"
    end

    test "fetches a configured key from the real Application env" do
      result = Mock.fetch_env(:trogon_test, :seeded_value)

      assert result == {:ok, "real value"}
    end

    test "fetches a configured key with fetch_env!/2 from the real Application env" do
      value = Mock.fetch_env!(:trogon_test, :seeded_value)

      assert value == "real value"
    end

    test "reads every key of the real Application env" do
      env = Mock.get_all_env(:trogon_test)

      assert Enum.sort(env) == Enum.sort(Application.get_all_env(:trogon_test))
    end
  end

  describe "expect_get_env/1" do
    test "returns the expected value" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      value = Mock.get_env(:trogon_test, :seeded_value, :default)

      assert value == "overridden"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value, :default)
    end

    test "covers as many calls as times" do
      TestApplication.expect_get_env(times: 2, returns: "overridden")

      values = [Mock.get_env(:trogon_test, :first, nil), Mock.get_env(:trogon_test, :second, nil)]

      assert values == ["overridden", "overridden"]
      TestApplication.assert_received_get_env(:trogon_test, :first)
      TestApplication.assert_received_get_env(:trogon_test, :second)
    end

    test "rejects a call past times" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      Mock.get_env(:trogon_test, :seeded_value, nil)

      assert_raise Mox.UnexpectedCallError, fn -> Mock.get_env(:trogon_test, :seeded_value, nil) end
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end

    test "leaves the real Application env untouched" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      Mock.get_env(:trogon_test, :seeded_value, nil)

      value = Application.get_env(:trogon_test, :seeded_value)

      assert value == "real value"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end
  end

  describe "expect_fetch_env/1" do
    test "returns the expected result" do
      TestApplication.expect_fetch_env(times: 1, returns: :error)

      result = Mock.fetch_env(:trogon_test, :seeded_value)

      assert result == :error
      TestApplication.assert_received_fetch_env(:trogon_test, :seeded_value)
    end
  end

  describe "expect_fetch_env!/1" do
    test "returns the expected value" do
      TestApplication.expect_fetch_env!(times: 1, returns: "overridden")

      value = Mock.fetch_env!(:trogon_test, :seeded_value)

      assert value == "overridden"
      TestApplication.assert_received_fetch_env!(:trogon_test, :seeded_value)
    end
  end

  describe "expect_get_all_env/1" do
    test "returns the expected env" do
      TestApplication.expect_get_all_env(times: 1, returns: [seeded_value: "overridden"])

      env = Mock.get_all_env(:trogon_test)

      assert env == [seeded_value: "overridden"]
      TestApplication.assert_received_get_all_env(:trogon_test)
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      value = Task.await(Task.async(fn -> Mock.get_env(:trogon_test, :seeded_value, nil) end))

      assert value == "overridden"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end

    test "reaches a process allowed with Mox.allow/3" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      parent = self()

      pid =
        spawn(fn ->
          receive do
            :read -> send(parent, {:read, Mock.get_env(:trogon_test, :seeded_value, nil)})
          end
        end)

      Mox.allow(Mock, self(), pid)

      send(pid, :read)

      assert_receive {:read, "overridden"}
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end
  end
end
