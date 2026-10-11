defmodule Trogon.Test.TestDateTimeTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockDateTime

  describe "stub/1" do
    test "reads the real clock" do
      before = DateTime.utc_now()

      now = MockDateTime.utc_now()

      assert DateTime.compare(now, before) in [:gt, :eq]
    end
  end

  describe "expect_utc_now/1" do
    test "returns the expected time" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      now = MockDateTime.utc_now()

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "covers as many calls as times" do
      TestDateTime.expect_utc_now(times: 2, returns: ~U[2026-01-01 00:00:00.000000Z])

      times = [MockDateTime.utc_now(), MockDateTime.utc_now()]

      assert times == [~U[2026-01-01 00:00:00.000000Z], ~U[2026-01-01 00:00:00.000000Z]]
      TestDateTime.assert_received_utc_now()
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a call past times" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])
      MockDateTime.utc_now()

      assert_raise Mox.UnexpectedCallError, fn -> MockDateTime.utc_now() end
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "rejects a value that is not a DateTime, which DateTime.utc_now/0 never returns" do
      assert %DateTime{} = DateTime.utc_now()

      assert_raise ArgumentError, fn -> TestDateTime.expect_utc_now(times: 1, returns: ~N[2026-01-01 00:00:00]) end
    end

    test "rejects a DateTime outside Etc/UTC, which DateTime.utc_now/0 never returns" do
      shifted = %{
        ~U[2026-01-01 00:00:00.000000Z]
        | time_zone: "America/New_York",
          zone_abbr: "EST",
          utc_offset: -18_000
      }

      assert DateTime.utc_now().time_zone == "Etc/UTC"

      assert_raise ArgumentError, fn -> TestDateTime.expect_utc_now(times: 1, returns: shifted) end
    end
  end

  describe "DateTime contract" do
    test "rejects a DateTime without microsecond precision, which DateTime.utc_now/0 never returns" do
      assert {_microsecond, 6} = DateTime.utc_now().microsecond

      assert_raise ArgumentError, fn -> TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z]) end
    end

    test "rejects a DateTime in another calendar, which DateTime.utc_now/0 never returns" do
      assert DateTime.utc_now().calendar == Calendar.ISO
      other = %{~U[2026-01-01 00:00:00.000000Z] | calendar: __MODULE__.OtherCalendar}

      assert_raise ArgumentError, fn -> TestDateTime.expect_utc_now(times: 1, returns: other) end
    end

    test "rejects an Etc/UTC DateTime with an offset, which DateTime.utc_now/0 never returns" do
      now = DateTime.utc_now()
      assert {now.zone_abbr, now.utc_offset, now.std_offset} == {"UTC", 0, 0}

      for field <- [utc_offset: 3_600, std_offset: 3_600, zone_abbr: "CET"] do
        offset = struct(~U[2026-01-01 00:00:00.000000Z], [field])
        assert_raise ArgumentError, fn -> TestDateTime.expect_utc_now(times: 1, returns: offset) end
      end
    end
  end

  describe "returns" do
    test "is required" do
      assert_raise KeyError, fn -> TestDateTime.expect_utc_now(times: 1) end
    end
  end

  describe "process ownership" do
    test "reaches the test's $callers" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      now = Task.await(Task.async(&MockDateTime.utc_now/0))

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
