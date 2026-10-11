defmodule Trogon.Test.TestTelemetryTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  setup %{test: test} do
    %{event: [__MODULE__, test]}
  end

  describe "attach/1" do
    test "forwards an event the test emits", %{event: event} do
      TestTelemetry.attach([event])

      :telemetry.execute(event, %{count: 1}, %{source: :test})

      TestTelemetry.assert_receive_event(^event, %{count: 1}, %{source: :test})
    end

    test "forwards an event a process in the test's $callers emits", %{event: event} do
      TestTelemetry.attach([event])

      Task.await(Task.async(fn -> :telemetry.execute(event, %{count: 1}, %{}) end))

      TestTelemetry.assert_receive_event(^event, %{count: 1}, _metadata)
    end

    test "ignores an event a process outside the test emits", %{event: event} do
      TestTelemetry.attach([event])
      test = self()

      spawn(fn ->
        :telemetry.execute(event, %{count: 1}, %{})
        send(test, :emitted)
      end)

      assert_receive :emitted
      TestTelemetry.refute_received_event(^event, _measurements, _metadata)
    end

    test "forwards every event it was given", %{event: event} do
      other = event ++ [:other]
      TestTelemetry.attach([event, other])

      :telemetry.execute(event, %{}, %{})
      :telemetry.execute(other, %{}, %{})

      TestTelemetry.assert_receive_event(^event, _measurements, _metadata)
      TestTelemetry.assert_receive_event(^other, _measurements, _metadata)
    end

    test "attaches one handler for the test", %{event: event} do
      TestTelemetry.attach([event])

      assert [%{function: function, config: config}] = :telemetry.list_handlers(event)
      assert function == (&TestTelemetry.handle_event/4)
      assert config == self()
    end

    test "leaves the mailbox checks alone", %{event: event} do
      TestTelemetry.attach([event])

      :telemetry.execute(event, %{}, %{})

      assert_receive {TestTelemetry, ^event, _measurements, _metadata}
      Trogon.Test.assert_empty_mailbox()
    end
  end

  describe "assert_receive_event/4" do
    test "waits up to the timeout it was given", %{event: event} do
      TestTelemetry.attach([event])

      task =
        Task.async(fn ->
          Process.sleep(10)
          :telemetry.execute(event, %{}, %{})
        end)

      TestTelemetry.assert_receive_event(^event, _measurements, _metadata, 1_000)
      Task.await(task)
    end

    test "fails when no matching event arrives", %{event: event} do
      TestTelemetry.attach([event])

      assert_raise ExUnit.AssertionError, fn ->
        TestTelemetry.assert_receive_event(^event, _measurements, _metadata, 0)
      end
    end
  end

  describe "refute_received_event/3" do
    test "fails when a matching event arrived", %{event: event} do
      TestTelemetry.attach([event])

      :telemetry.execute(event, %{}, %{})

      assert_raise ExUnit.AssertionError, fn ->
        TestTelemetry.refute_received_event(^event, _measurements, _metadata)
      end
    end
  end
end
