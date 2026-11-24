defmodule Trogon.Commanded.TestSupport.TestCommandRouterTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  alias Acme.Billing
  alias Acme.Billing.ChargeCard
  alias Commanded.Commands.ExecutionResult
  alias Trogon.Commanded.TestSupport.MockCommandRouter
  alias Trogon.Commanded.TestSupport.TestCommandRouter
  alias Trogon.Test.Recorder

  require TestCommandRouter

  describe "expect_dispatch/1" do
    test "records the dispatch and returns :ok by default" do
      TestCommandRouter.expect_dispatch()

      assert :ok = Billing.charge("card-1", 1_000)

      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])
      Trogon.Test.assert_empty_mailbox()
    end

    test "records the options the dispatch was given" do
      TestCommandRouter.expect_dispatch()

      Billing.charge("card-1", 1_000, timeout: 5_000)

      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, timeout: 5_000)
    end

    test "returns the given value" do
      result = %ExecutionResult{
        aggregate_uuid: "card-1",
        aggregate_state: %{},
        aggregate_version: 3,
        events: [],
        metadata: %{}
      }

      for returns <- [:ok, {:ok, %{balance: 0}}, {:ok, result}, {:error, :card_declined}] do
        TestCommandRouter.expect_dispatch(returns: returns)

        assert Billing.charge("card-1", 1_000) == returns
        TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])
      end
    end

    test "covers as many dispatches as :times" do
      TestCommandRouter.expect_dispatch(times: 2)

      assert :ok = Billing.charge("card-1", 1_000)
      assert :ok = Billing.charge("card-2", 2_000)

      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])
      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-2", cents: 2_000}, [])
      assert_raise Mox.UnexpectedCallError, fn -> Billing.charge("card-3", 3_000) end
    end

    test "records a dispatch from a task of the test" do
      TestCommandRouter.expect_dispatch()

      assert :ok = Task.await(Task.async(fn -> Billing.charge("card-1", 1_000) end))

      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])
    end

    test "records a dispatch from an allowed process" do
      TestCommandRouter.expect_dispatch()
      supervisor = start_supervised!(Task.Supervisor)
      Mox.allow(MockCommandRouter, self(), supervisor)

      task = Task.Supervisor.async_nolink(supervisor, fn -> Billing.charge("card-1", 1_000) end)

      assert Task.await(task) == :ok
      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])
    end

    test "fails verification for a dispatch no assertion covers" do
      tracker = Recorder.start_tracking()
      TestCommandRouter.expect_dispatch()

      Billing.charge("card-1", 1_000)

      error = assert_raise ExUnit.AssertionError, fn -> Recorder.verify!(tracker) end
      assert error.message =~ "ChargeCard"
      Recorder.stop_tracking(tracker)
    end

    test "passes verification once the dispatch is asserted" do
      tracker = Recorder.start_tracking()
      TestCommandRouter.expect_dispatch()

      Billing.charge("card-1", 1_000)
      TestCommandRouter.assert_received_dispatch(%ChargeCard{card_id: "card-1", cents: 1_000}, [])

      assert Recorder.verify!(tracker) == :ok
      Recorder.stop_tracking(tracker)
    end

    test "raises on an invalid :returns" do
      for returns <- [:error, nil, "ok", {:ok}, {:error}] do
        assert_raise NimbleOptions.ValidationError, ~r/expected :returns to be/, fn ->
          TestCommandRouter.expect_dispatch(returns: returns)
        end
      end
    end

    test "raises on an invalid :times" do
      for times <- [-1, 1.5, :once, nil] do
        assert_raise NimbleOptions.ValidationError, ~r/invalid value for :times option/, fn ->
          TestCommandRouter.expect_dispatch(times: times)
        end
      end
    end

    test "raises on an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:count\]/, fn ->
        TestCommandRouter.expect_dispatch(count: 2)
      end
    end
  end
end
