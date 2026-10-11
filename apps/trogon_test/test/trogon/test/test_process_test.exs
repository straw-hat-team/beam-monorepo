defmodule Trogon.Test.TestProcessTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockProcess

  describe "stub/1" do
    test "schedules the message with the real Process" do
      MockProcess.send_after(self(), :tick, 0, [])

      assert_receive :tick
    end

    test "sleeps with the real Process" do
      result = MockProcess.sleep(0)

      assert result == :ok
    end
  end

  describe "expect_send_after/1" do
    test "returns the expected timer without scheduling the message" do
      timer = make_ref()
      TestProcess.expect_send_after(times: 1, returns: timer)

      result = MockProcess.send_after(self(), :tick, 0, [])

      assert result == timer
      TestProcess.assert_received_send_after(self(), :tick, 0)
      refute_receive :tick
      Trogon.Test.assert_empty_mailbox()
    end

    test "returns a new reference without returns" do
      TestProcess.expect_send_after(times: 1)

      result = MockProcess.send_after(self(), :tick, 1_000, [])

      assert is_reference(result)
      TestProcess.assert_received_send_after(self(), :tick, 1_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "records the options it was given" do
      TestProcess.expect_send_after(times: 1)

      MockProcess.send_after(self(), :tick, 1_000, abs: false)

      TestProcess.assert_received_send_after(self(), :tick, 1_000, abs: false)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestProcess.expect_send_after(times: 2)

      MockProcess.send_after(self(), :first, 1_000, [])
      MockProcess.send_after(self(), :second, 2_000, [])

      TestProcess.assert_received_send_after(self(), :first, 1_000)
      TestProcess.assert_received_send_after(self(), :second, 2_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "returns a new reference for each call by default" do
      TestProcess.expect_send_after(times: 2)

      first = MockProcess.send_after(self(), :first, 1_000, [])
      second = MockProcess.send_after(self(), :second, 1_000, [])

      assert first != second
      TestProcess.assert_received_send_after(self(), :first, 1_000)
      TestProcess.assert_received_send_after(self(), :second, 1_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "returns the given reference for every call" do
      timer = make_ref()
      TestProcess.expect_send_after(times: 2, returns: timer)

      assert MockProcess.send_after(self(), :first, 1_000, []) == timer
      assert MockProcess.send_after(self(), :second, 1_000, []) == timer
      TestProcess.assert_received_send_after(self(), :first, 1_000)
      TestProcess.assert_received_send_after(self(), :second, 1_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestProcess.expect_send_after(times: 1)
      MockProcess.send_after(self(), :tick, 1_000, [])

      assert_raise Mox.UnexpectedCallError, fn -> MockProcess.send_after(self(), :tick, 1_000, []) end
      TestProcess.assert_received_send_after(self(), :tick, 1_000)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "expect_sleep/1" do
    test "returns without sleeping" do
      TestProcess.expect_sleep(times: 1)

      result = MockProcess.sleep(:infinity)

      assert result == :ok
      TestProcess.assert_received_sleep(:infinity)
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestProcess.expect_sleep(times: 2)

      MockProcess.sleep(100)
      MockProcess.sleep(200)

      TestProcess.assert_received_sleep(100)
      TestProcess.assert_received_sleep(200)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestProcess.expect_sleep(times: 1)
      MockProcess.sleep(100)

      assert_raise Mox.UnexpectedCallError, fn -> MockProcess.sleep(100) end
      TestProcess.assert_received_sleep(100)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "send_after/4 contract" do
    test "rejects a negative time, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, -1) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, -1, []) end
    end

    test "rejects a time that is not an integer, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, :infinity) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, :infinity, []) end
    end

    test "rejects a dest that is neither a pid nor an atom, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after({:poller, node()}, :tick, 1_000) end
      assert_raise ArgumentError, fn -> MockProcess.send_after({:poller, node()}, :tick, 1_000, []) end
    end

    test "rejects an option other than abs: boolean, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, 1_000, abs: 1) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, 1_000, abs: 1) end
    end

    test "accepts an absolute time from the monotonic clock, which can be negative, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)
      time = System.monotonic_time(:millisecond)
      Process.send_after(self(), :real_tick, time, abs: true)
      assert_receive :real_tick

      MockProcess.send_after(self(), :tick, time, abs: true)

      TestProcess.assert_received_send_after(self(), :tick, time, abs: true)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects an absolute time before the VM start, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)
      start = System.convert_time_unit(:erlang.system_info(:start_time), :native, :millisecond)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, start - 1, abs: true) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, start - 1, abs: true) end
    end

    test "rejects an absolute time that is not an integer, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, 1.5, abs: true) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, 1.5, abs: true) end
    end

    test "takes the last abs option, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, -1, abs: true, abs: false) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, -1, abs: true, abs: false) end
    end

    test "rejects an option other than abs, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, 1_000, foo: true) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, 1_000, foo: true) end
    end

    test "rejects options that are not a list, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)

      assert_raise ArgumentError, fn -> Process.send_after(self(), :tick, 1_000, %{abs: true}) end
      assert_raise ArgumentError, fn -> MockProcess.send_after(self(), :tick, 1_000, %{abs: true}) end
    end

    test "accepts a name nothing registered, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)
      refute Process.whereis(__MODULE__.Nobody)
      Process.cancel_timer(Process.send_after(__MODULE__.Nobody, :tick, 1_000))

      MockProcess.send_after(__MODULE__.Nobody, :tick, 1_000, [])

      TestProcess.assert_received_send_after(__MODULE__.Nobody, :tick, 1_000)
      Trogon.Test.assert_empty_mailbox()
    end

    test "accepts a zero time, as Process.send_after/4 does" do
      TestProcess.expect_send_after(times: 1)
      Process.send_after(self(), :real_tick, 0)

      MockProcess.send_after(self(), :tick, 0, [])

      assert_receive :real_tick
      TestProcess.assert_received_send_after(self(), :tick, 0)
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects returns: other than a reference, which Process.send_after/4 never returns" do
      assert is_reference(Process.send_after(self(), :tick, 1_000))

      assert_raise ArgumentError, fn -> TestProcess.expect_send_after(times: 1, returns: :timer) end
    end
  end

  describe "sleep/1 contract" do
    test "rejects a negative timeout, as Process.sleep/1 does" do
      TestProcess.expect_sleep(times: 1)

      assert_raise FunctionClauseError, fn -> Process.sleep(-1) end
      assert_raise FunctionClauseError, fn -> MockProcess.sleep(-1) end
    end

    test "rejects a timeout that is not an integer or :infinity, as Process.sleep/1 does" do
      TestProcess.expect_sleep(times: 1)

      assert_raise FunctionClauseError, fn -> Process.sleep(1.5) end
      assert_raise FunctionClauseError, fn -> MockProcess.sleep(1.5) end
    end

    test "accepts a zero timeout, as Process.sleep/1 does" do
      TestProcess.expect_sleep(times: 1)

      results = [Process.sleep(0), MockProcess.sleep(0)]

      assert results == [:ok, :ok]
      TestProcess.assert_received_sleep(0)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "assert_received_*" do
    test "fails on a call given other arguments" do
      TestProcess.expect_send_after(times: 1)
      TestProcess.expect_sleep(times: 1)

      MockProcess.send_after(self(), :tick, 1_000, abs: false)
      MockProcess.sleep(100)

      assert_raise ExUnit.AssertionError, fn -> TestProcess.assert_received_send_after(self(), :tock, 1_000) end
      assert_raise ExUnit.AssertionError, fn -> TestProcess.assert_received_send_after(self(), :tick, 2_000) end

      assert_raise ExUnit.AssertionError, fn ->
        TestProcess.assert_received_send_after(self(), :tick, 1_000, abs: true)
      end

      assert_raise ExUnit.AssertionError, fn -> TestProcess.assert_received_sleep(200) end
      TestProcess.assert_received_send_after(self(), :tick, 1_000, abs: false)
      TestProcess.assert_received_sleep(100)
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "process ownership" do
    test "reaches a named process allowed before it starts" do
      TestProcess.expect_send_after(times: 1)
      Trogon.Test.allow(__MODULE__.Poller)

      start_supervised!(%{
        id: __MODULE__.Poller,
        start: {Agent, :start_link, [fn -> nil end, [name: __MODULE__.Poller]]}
      })

      Agent.get(__MODULE__.Poller, fn _state -> MockProcess.send_after(__MODULE__.Poller, :poll, 5_000, []) end)

      TestProcess.assert_received_send_after(__MODULE__.Poller, :poll, 5_000)
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
