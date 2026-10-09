defmodule Trogon.Dispatcher.TelemetryTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.TestSupport, as: Support

  require Trogon.Dispatcher.Test, as: Test

  describe "start event" do
    setup do
      Test.attach_telemetry!()
      :ok
    end

    test "carries the compile-time facts and the context" do
      options = DispatchOptions.new!(correlation_id: "corr", actor: :someone, assigns: %{trail: []})
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      metadata = Test.assert_dispatch_start(Support.RegisterUser)

      assert metadata.message == %Support.RegisterUser{email: "a@b.c"}
      assert metadata.kind == :command
      assert metadata.dispatcher == Support.RootDispatcher
      assert metadata.registered_by == Support.AccountsDispatcher
      assert metadata.handler == Support.RegisterUser
      assert metadata.context.correlation_id == "corr"
      assert metadata.context.actor == :someone
      assert metadata.context.message == %Support.RegisterUser{email: "a@b.c"}
    end

    test "reports the kind of a query" do
      Support.RootDispatcher.dispatch_message(%Support.GetUser{id: 1}, DispatchOptions.new!(assigns: %{trail: []}))

      metadata = Test.assert_dispatch_start(Support.GetUser)

      assert metadata.kind == :query
    end
  end

  describe "stop event" do
    setup do
      Test.attach_telemetry!()
      :ok
    end

    test "reports success as a flat result dimension" do
      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :ok
      refute Map.has_key?(metadata, :error)
    end

    test "reports failure and carries the error term" do
      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, DispatchOptions.new!(assigns: %{trail: []}))

      metadata = Test.assert_dispatch_stop(Support.FailingCommand)

      assert metadata.result == :error
      assert metadata.error == :nope
    end

    test "counts a middleware short circuit as a failure" do
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, DispatchOptions.new!(actor: :forbidden))

      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

      assert metadata.result == :error
      assert metadata.error == :unauthorized
    end
  end

  describe "exception event" do
    setup do
      Test.attach_telemetry!()
      :ok
    end

    test "fires when the handler raises and still lets the exception through" do
      assert_raise RuntimeError, "boom", fn ->
        Support.RootDispatcher.dispatch_message(
          %Support.ExplodingCommand{},
          DispatchOptions.new!(assigns: %{trail: []})
        )
      end

      metadata = Test.assert_dispatch_exception(Support.ExplodingCommand)

      assert metadata.kind == :error
      assert %RuntimeError{message: "boom"} = metadata.reason
      assert is_list(metadata.stacktrace)
    end
  end

  describe "events" do
    test "a dispatch through an importer emits once, naming the entry point and the registering dispatcher" do
      Test.attach_telemetry!()

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, DispatchOptions.new!(assigns: %{trail: []}))

      Test.assert_dispatch_start(Support.RegisterUser)
      metadata = Test.assert_dispatch_stop(Support.RegisterUser)

      assert metadata.dispatcher == Support.RootDispatcher
      assert metadata.registered_by == Support.AccountsDispatcher
      Test.refute_dispatch(Support.RegisterUser)
    end
  end

  describe "refute_dispatch/1" do
    test "passes when the message was never dispatched" do
      Test.attach_telemetry!()

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{}, DispatchOptions.new!(assigns: %{trail: []}))

      Test.refute_dispatch(Support.GetUser)
    end
  end
end
