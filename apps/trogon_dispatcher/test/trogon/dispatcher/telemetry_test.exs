defmodule Trogon.Dispatcher.TelemetryTest do
  use ExUnit.Case, async: true

  import Trogon.Dispatcher.Test

  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.TestSupport, as: Support

  describe "start event" do
    setup do
      attach_telemetry!([:support, :root])
      :ok
    end

    test "carries the compile-time facts and the context" do
      options = %DispatchOptions{correlation_id: "corr", actor: :someone, assigns: %{trail: []}}
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      metadata = assert_dispatch_start(Support.RegisterUser)

      assert metadata.message == Support.RegisterUser
      assert metadata.kind == :command
      assert metadata.dispatcher == Support.RootDispatcher
      assert metadata.registered_by == Support.AccountsDispatcher
      assert metadata.context.correlation_id == "corr"
      assert metadata.context.actor == :someone
      assert metadata.context.message == %Support.RegisterUser{email: "a@b.c"}
    end

    test "reports the kind of a query" do
      Support.RootDispatcher.dispatch_message(%Support.GetUser{id: 1}, %DispatchOptions{assigns: %{trail: []}})

      metadata = assert_dispatch_start(Support.GetUser)

      assert metadata.kind == :query
    end
  end

  describe "stop event" do
    setup do
      attach_telemetry!([:support, :root])
      :ok
    end

    test "reports success as a flat result dimension" do
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{
        assigns: %{trail: []}
      })

      metadata = assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :ok
      refute Map.has_key?(metadata, :error)
    end

    test "reports failure and carries the error term" do
      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, %DispatchOptions{assigns: %{trail: []}})

      metadata = assert_dispatch_stop(Support.FailingCommand)

      assert metadata.result == :error
      assert metadata.error == :nope
    end

    test "counts a middleware short circuit as a failure" do
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, %DispatchOptions{actor: :forbidden})

      metadata = assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :error
      assert metadata.error == :unauthorized
    end

    test "measures the whole dispatch including middleware" do
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:trogon_dispatcher_telemetry, :stop, _event, measurements, _metadata}
      assert measurements.duration > 0
    end
  end

  describe "exception event" do
    setup do
      attach_telemetry!([:support, :root])
      :ok
    end

    test "fires when the handler raises and still lets the exception through" do
      assert_raise RuntimeError, "boom", fn ->
        Support.RootDispatcher.dispatch_message(%Support.ExplodingCommand{}, %DispatchOptions{assigns: %{trail: []}})
      end

      metadata = assert_dispatch_exception(Support.ExplodingCommand)

      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason
      assert is_list(metadata.stacktrace)
    end
  end

  describe "telemetry prefix" do
    test "a dispatcher emits under its own configured prefix" do
      attach_telemetry!([:support, :root])

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:trogon_dispatcher_telemetry, :start, [:support, :root, :dispatch, :start], _m, _meta}
    end

    test "a dispatcher without a configured prefix emits under the default" do
      attach_telemetry!()

      Support.AccountsDispatcher.dispatch_message(%Support.RegisterUser{})

      assert_receive {:trogon_dispatcher_telemetry, :start, [:trogon_dispatcher, :dispatch, :start], _m, _meta}
    end

    test "only the dispatcher that was called emits" do
      attach_telemetry!([:support, :root])
      attach_telemetry!()

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:trogon_dispatcher_telemetry, :stop, [:support, :root, :dispatch, :stop], _m, _meta}
      refute_receive {:trogon_dispatcher_telemetry, _phase, [:trogon_dispatcher, :dispatch, _], _m, _meta}
    end
  end

  describe "refute_dispatch/1" do
    test "passes when the message was never dispatched" do
      attach_telemetry!([:support, :root])

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, %DispatchOptions{assigns: %{trail: []}})

      refute_dispatch(Support.GetUser)
    end
  end
end
