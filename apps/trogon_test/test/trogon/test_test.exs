defmodule Trogon.TestTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Trogon.Test.MockApplication
  alias Trogon.Test.MockDateTime
  alias Trogon.Test.MockProcess
  alias Trogon.Test.MockRand
  alias Trogon.Test.MockTask
  alias Trogon.Test.MockUUID
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
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

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
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

      MockDateTime.utc_now()

      message = assert_received({Trogon.Test, {TestDateTime, {:utc_now, []}}})
      assert_raise ExUnit.AssertionError, fn -> Recorder.verify!() end
      Recorder.asserted(message)
    end

    test "tracks a call from a process the test started" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

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

    test "reaches a process allowed by a global name" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])
      name = {:global, {__MODULE__, make_ref()}}
      Trogon.Test.allow(name)
      start_supervised!(%{id: name, start: {Agent, :start_link, [fn -> nil end, [name: name]]}})

      now = Agent.get(name, fn _state -> MockDateTime.utc_now() end)

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "reaches a process allowed by a via name" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])
      registry = start_supervised!({Registry, keys: :unique, name: Module.concat(__MODULE__, Registry)})
      assert is_pid(registry)
      name = {:via, Registry, {Module.concat(__MODULE__, Registry), :clock}}
      Trogon.Test.allow(name)
      start_supervised!(%{id: :clock, start: {Agent, :start_link, [fn -> nil end, [name: name]]}})

      now = Agent.get(name, fn _state -> MockDateTime.utc_now() end)

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end

    test "reaches every mock from one allowance" do
      TestApplication.expect_get_env(times: 1, returns: "overridden")
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])
      TestProcess.expect_sleep(times: 1)
      TestRand.expect_uniform(times: 1, returns: 1)
      TestTask.expect_async(times: 1)
      TestUUID.expect_uuid7(times: 1, returns: "01a128c8-383e-7f3b-8f53-5fa308ac0d07")
      agent = start_supervised!({Agent, fn -> nil end})
      Trogon.Test.allow(agent)

      result =
        Agent.get(agent, fn _state ->
          MockApplication.get_env(:trogon_test, :seeded_value, nil)
          MockDateTime.utc_now()
          MockProcess.sleep(100)
          MockRand.uniform(1)
          MockUUID.uuid7(:default)
          Task.await(MockTask.async(fn -> :ran end))
        end)

      assert result == :ran

      TestApplication.assert_received_get_env(:trogon_test, :seeded_value)
      TestDateTime.assert_received_utc_now()
      TestProcess.assert_received_sleep(100)
      TestRand.assert_received_uniform(1)
      TestUUID.assert_received_uuid7()
      Trogon.Test.assert_empty_mailbox()
    end

    test "reaches a named process allowed before it starts" do
      TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])
      Trogon.Test.allow(__MODULE__.Clock)
      start_supervised!(%{id: __MODULE__.Clock, start: {Agent, :start_link, [fn -> nil end, [name: __MODULE__.Clock]]}})

      now = Agent.get(__MODULE__.Clock, fn _state -> MockDateTime.utc_now() end)

      assert now == ~U[2026-01-01 00:00:00.000000Z]
      TestDateTime.assert_received_utc_now()
      Trogon.Test.assert_empty_mailbox()
    end
  end
end
