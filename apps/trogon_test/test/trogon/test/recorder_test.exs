defmodule Trogon.Test.RecorderTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.AcmeMailer
  alias Trogon.Test.Recorder

  require AcmeMailer

  describe "a source module outside trogon_test" do
    setup {Trogon.Test, :verify_mailbox_on_exit!}

    test "sends the recorded call to the test process" do
      AcmeMailer.expect_deliver("ada@example.com").()

      assert_received {Trogon.Test, {AcmeMailer, {:deliver, ["ada@example.com"]}}}
      Recorder.asserted({Trogon.Test, {AcmeMailer, {:deliver, ["ada@example.com"]}}})
    end

    test "passes verification once its assert macro ran" do
      AcmeMailer.expect_deliver("ada@example.com").()

      AcmeMailer.assert_received_deliver("ada@example.com")

      assert :ok = Recorder.verify!()
    end

    test "fails verification while a call is unasserted" do
      AcmeMailer.expect_deliver("ada@example.com").()

      assert_raise ExUnit.AssertionError, ~r/AcmeMailer.*ada@example.com/s, &Recorder.verify!/0
      AcmeMailer.assert_received_deliver("ada@example.com")
    end

    test "records a call made from another process" do
      expectation = AcmeMailer.expect_deliver("ada@example.com")

      expectation |> Task.async() |> Task.await()

      assert_raise ExUnit.AssertionError, ~r/ada@example.com/, &Recorder.verify!/0
      AcmeMailer.assert_received_deliver("ada@example.com")
      assert :ok = Recorder.verify!()
    end
  end

  describe "without verify_mailbox_on_exit!" do
    test "still sends the call to the owner" do
      AcmeMailer.expect_deliver("ada@example.com").()

      AcmeMailer.assert_received_deliver("ada@example.com")
    end
  end
end
