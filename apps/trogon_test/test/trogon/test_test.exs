defmodule Trogon.TestTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.MockApplication
  alias Trogon.Test.MockDateTime
  alias Trogon.Test.TestApplication
  alias Trogon.Test.TestDateTime

  require TestApplication
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
end
