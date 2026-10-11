defmodule Trogon.Test.TestDateTimeTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.TestDateTime
  alias Trogon.Test.TestDateTime.MockDateTime

  require TestDateTime

  setup :verify_on_exit!
  setup {TestDateTime, :stub}

  describe "stub/1" do
    test "reads the real clock" do
      before = DateTime.utc_now()

      now = MockDateTime.utc_now()

      assert DateTime.compare(now, before) in [:gt, :eq]
    end
  end

  describe "expect_utc_now/1" do
    test "returns the expected time" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

      now = MockDateTime.utc_now()

      assert now == ~U[2026-01-01 00:00:00Z]
      TestDateTime.assert_received_utc_now()
    end

    test "covers as many calls as times" do
      TestDateTime.expect_utc_now(times: 2, returns: ~U[2026-01-01 00:00:00Z])

      times = [MockDateTime.utc_now(), MockDateTime.utc_now()]

      assert times == [~U[2026-01-01 00:00:00Z], ~U[2026-01-01 00:00:00Z]]
      TestDateTime.assert_received_utc_now()
      TestDateTime.assert_received_utc_now()
    end

    test "rejects a call past times" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])
      MockDateTime.utc_now()

      assert_raise Mox.UnexpectedCallError, fn -> MockDateTime.utc_now() end
      TestDateTime.assert_received_utc_now()
    end

    test "rejects a value that is not a DateTime" do
      assert_raise MatchError, fn -> TestDateTime.expect_utc_now(times: 1, returns: ~N[2026-01-01 00:00:00]) end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

      now = Task.await(Task.async(&MockDateTime.utc_now/0))

      assert now == ~U[2026-01-01 00:00:00Z]
      TestDateTime.assert_received_utc_now()
    end
  end
end
