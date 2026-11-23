defmodule Trogon.TestGlobalModeTest do
  use ExUnit.Case, async: false
  use Trogon.Test

  alias Trogon.Test.MockDateTime

  @now ~U[2026-01-01 00:00:00.000000Z]

  test "reaches a process the test never allowed, since the test is not async" do
    TestDateTime.expect_utc_now(times: 1, returns: @now)
    agent = start_supervised!({Agent, fn -> nil end})

    now = Agent.get(agent, fn _state -> MockDateTime.utc_now() end)

    assert now == @now
    TestDateTime.assert_received_utc_now()
    Trogon.Test.assert_empty_mailbox()
  end

  test "accepts allow/1, which global mode already covers" do
    TestDateTime.expect_utc_now(times: 1, returns: @now)
    agent = start_supervised!({Agent, fn -> nil end})
    Trogon.Test.allow(agent)

    now = Agent.get(agent, fn _state -> MockDateTime.utc_now() end)

    assert now == @now
    TestDateTime.assert_received_utc_now()
    Trogon.Test.assert_empty_mailbox()
  end
end
