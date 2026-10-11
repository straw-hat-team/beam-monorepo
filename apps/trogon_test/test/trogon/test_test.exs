defmodule Trogon.TestTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockApplication
  alias Trogon.Test.MockDateTime
  alias Trogon.Test.Recorder

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

  describe "verify_mailbox_on_exit!/1" do
    setup {Trogon.Test, :verify_mailbox_on_exit!}

    test "passes once every recorded call is asserted" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end

    test "fails on a recorded call left unasserted" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")

      MockApplication.get_env(:trogon_test, :seeded_value, nil)

      assert_raise ExUnit.AssertionError, ~r/:seeded_value/, fn -> Recorder.verify!() end
      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
    end

    test "counts a call consumed with plain assert_received as unasserted" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

      MockDateTime.utc_now()

      message = assert_received({Trogon.Test, {TestDateTime, {:utc_now, []}}})
      assert_raise ExUnit.AssertionError, fn -> Recorder.verify!() end
      Recorder.asserted(message)
    end

    test "tracks a call from a process the test started" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

      Task.await(Task.async(fn -> MockDateTime.utc_now() end))

      assert_raise ExUnit.AssertionError, fn -> Recorder.verify!() end
      TestDateTime.assert_received_utc_now()
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
