defmodule Trogon.TestTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.MockApplication
  alias Trogon.Test.MockDateTime
  alias Trogon.Test.TestApplication
  alias Trogon.Test.TestDateTime

  require TestApplication
  require TestDateTime
  require Trogon.Test

  setup :verify_on_exit!
  setup {TestApplication, :stub}
  setup {TestDateTime, :stub}

  describe "assert_empty_mailbox/0" do
    test "passes once every recorded call is asserted" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end

    test "fails on a recorded call left unasserted" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

      MockApplication.get_env(:trogon_test, :seeded_value, nil)
      MockDateTime.utc_now()

      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      assert_raise ExUnit.AssertionError, fn -> Trogon.Test.assert_empty_mailbox() end
    end

    test "ignores messages no mock sent" do
      send(self(), {:unrelated, :message})

      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "allow/1" do
    test "reaches a process allowed by pid" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      agent = start_supervised!({Agent, fn -> nil end})
      Trogon.Test.allow(agent)

      value = Agent.get(agent, fn _state -> MockApplication.get_env(:trogon_test, :seeded_value, nil) end)

      assert value == "overridden"
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      Trogon.Test.assert_empty_mailbox()
    end

    test "reaches a named process allowed before it starts" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])
      Trogon.Test.allow(__MODULE__.Clock)
      start_supervised!(%{id: __MODULE__.Clock, start: {Agent, :start_link, [fn -> nil end, [name: __MODULE__.Clock]]}})

      now = Agent.get(__MODULE__.Clock, fn _state -> MockDateTime.utc_now() end)

      assert now == ~U[2026-01-01 00:00:00Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
