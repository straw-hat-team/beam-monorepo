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

  describe "stub_env/3" do
    test "overrides only the given key with a literal value" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "overridden")

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "overridden"
      assert MockApplication.get_env(:trogon_test, :seeded_list, nil) == [a: 1, b: 2]
    end

    test "gives a function the real value" do
      TestApplication.stub_env(:trogon_test, :seeded_list, &Keyword.merge(&1, b: 3, c: 4))

      assert MockApplication.get_env(:trogon_test, :seeded_list, nil) == [a: 1, b: 3, c: 4]
    end

    test "gives a function the caller's default when the key is unset" do
      TestApplication.stub_env(:trogon_test, :unset_key, &Keyword.put(&1, :a, 1))

      assert MockApplication.get_env(:trogon_test, :unset_key, []) == [a: 1]
    end

    test "returns a literal override of an unset key" do
      TestApplication.stub_env(:trogon_test, :unset_key, "overridden")

      assert MockApplication.get_env(:trogon_test, :unset_key, :default) == "overridden"
    end

    test "returns a function value when wrapped" do
      fun = fn -> :config_fun end
      TestApplication.stub_env(:trogon_test, :seeded_value, fn _real -> fun end)

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == fun
    end

    test "does not affect other apps with the same key" do
      TestApplication.stub_env(:other_app, :seeded_value, "overridden")

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "real value"
    end

    test "overrides fetch_env/2" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "overridden")

      assert MockApplication.fetch_env(:trogon_test, :seeded_value) == {:ok, "overridden"}
      assert MockApplication.fetch_env(:trogon_test, :seeded_list) == {:ok, [a: 1, b: 2]}
    end

    test "overrides an unset key for fetch_env/2 and gives a function nil" do
      TestApplication.stub_env(:trogon_test, :unset_key, &(&1 || "from nil"))

      assert MockApplication.fetch_env(:trogon_test, :unset_key) == {:ok, "from nil"}
    end

    test "overrides fetch_env!/2" do
      TestApplication.stub_env(:trogon_test, :seeded_value, &(&1 <> " changed"))

      assert MockApplication.fetch_env!(:trogon_test, :seeded_value) == "real value changed"
      assert MockApplication.fetch_env!(:trogon_test, :seeded_list) == [a: 1, b: 2]
    end

    test "overrides get_all_env/1" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "overridden")
      TestApplication.stub_env(:trogon_test, :added_key, "added")

      env = MockApplication.get_all_env(:trogon_test)

      assert env[:seeded_value] == "overridden"
      assert env[:added_key] == "added"
      assert env[:seeded_list] == [a: 1, b: 2]
    end

    test "does not change get_all_env/1 of another app" do
      TestApplication.stub_env(:other_app, :seeded_value, "overridden")

      env = MockApplication.get_all_env(:trogon_test)

      assert env[:seeded_value] == "real value"
    end

    test "keeps every override of different keys" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "first")
      TestApplication.stub_env(:trogon_test, :seeded_list, [:second])

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "first"
      assert MockApplication.get_env(:trogon_test, :seeded_list, nil) == [:second]
    end

    test "applies overrides of the same key in call order" do
      TestApplication.stub_env(:trogon_test, :seeded_list, &Keyword.put(&1, :a, 10))
      TestApplication.stub_env(:trogon_test, :seeded_list, &Keyword.put(&1, :c, 3))

      assert Enum.sort(MockApplication.get_env(:trogon_test, :seeded_list, nil)) == [a: 10, b: 2, c: 3]
    end

    test "lets a later literal replace an earlier override of the same key" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "first")
      TestApplication.stub_env(:trogon_test, :seeded_value, "last")

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "last"
    end

    test "keeps an expectation ahead of the stub" do
      TestApplication.expect_get_env(times: 1, returns: "expected")
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "expected"
      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "stubbed"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end

    test "loses the stub of a function expected after it" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")
      TestApplication.expect_get_env(times: 1, returns: "expected")

      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      assert_raise Mox.UnexpectedCallError, fn -> MockApplication.get_env(:trogon_test, :seeded_value, nil) end
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end

    test "does not record reads" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")

      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      Trogon.Test.assert_empty_mailbox()
    end

    test "is dropped by stub/1" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")
      TestApplication.stub()
      TestApplication.stub_env(:trogon_test, :seeded_list, [:only])

      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "real value"
      assert MockApplication.get_env(:trogon_test, :seeded_list, nil) == [:only]
    end

    test "reaches a Task spawned by the test" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")

      value = Task.await(Task.async(fn -> MockApplication.get_env(:trogon_test, :seeded_value, nil) end))

      assert value == "stubbed"
    end

    test "reaches a process allowed with Trogon.Test.allow/1" do
      TestApplication.stub_env(:trogon_test, :seeded_value, "stubbed")
      parent = self()

      pid =
        spawn(fn ->
          receive do
            :read -> send(parent, {:read, MockApplication.get_env(:trogon_test, :seeded_value, nil)})
          end
        end)

      Trogon.Test.allow(pid)

      send(pid, :read)

      assert_receive {:read, "stubbed"}
    end

    test "does not leak into the next test" do
      assert MockApplication.get_env(:trogon_test, :seeded_value, nil) == "real value"
    end
  end
end
