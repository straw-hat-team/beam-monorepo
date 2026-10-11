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
