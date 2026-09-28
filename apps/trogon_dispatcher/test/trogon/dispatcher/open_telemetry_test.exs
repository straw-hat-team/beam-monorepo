defmodule Trogon.Dispatcher.OpenTelemetryTest do
  use Trogon.Dispatcher.OpenTelemetryCase, async: false

  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.OpenTelemetry, as: DispatcherOpenTelemetry
  alias Trogon.Dispatcher.OpenTelemetryCase
  alias Trogon.Dispatcher.TestSupport, as: Support

  require OpenTelemetry.Tracer, as: Tracer

  setup do
    OpenTelemetryCase.detach_handlers()
    DispatcherOpenTelemetry.setup()
    :ok
  end

  describe "setup/1" do
    test "attaches a handler for every dispatch event" do
      for event <- [
            [:trogon_dispatcher, :dispatch, :start],
            [:trogon_dispatcher, :dispatch, :stop],
            [:trogon_dispatcher, :dispatch, :exception]
          ] do
        handlers = :telemetry.list_handlers(event)

        assert Enum.any?(handlers, &match?(%{id: {DispatcherOpenTelemetry, :dispatch}}, &1)),
               "expected a handler attached for #{inspect(event)}"
      end
    end

    test "calling setup/1 twice raises MatchError" do
      assert_raise MatchError, fn -> DispatcherOpenTelemetry.setup() end
    end
  end

  describe "successful dispatch" do
    test "starts a span named after the operation and destination, kind internal, with messaging attributes" do
      options = %DispatchOptions{correlation_id: "corr-1", causation_id: "cause-1", assigns: %{trail: []}}
      assert {:ok, _user} = Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(name: name, kind: kind, attributes: attributes)}, 1000

      assert name == "dispatch #{inspect(Support.RegisterUser)}"
      assert kind == :internal

      assert :otel_attributes.map(attributes) == %{
               "messaging.system": "trogon_dispatcher",
               "messaging.operation.name": "dispatch",
               "messaging.operation.type": "process",
               "messaging.destination.name": inspect(Support.RegisterUser),
               "messaging.message.conversation_id": "corr-1",
               "trogon_dispatcher.message": inspect(Support.RegisterUser),
               "trogon_dispatcher.kind": "command",
               "trogon_dispatcher.dispatcher": inspect(Support.RootDispatcher),
               "trogon_dispatcher.registered_by": inspect(Support.AccountsDispatcher),
               "trogon_dispatcher.correlation_id": "corr-1",
               "trogon_dispatcher.causation_id": "cause-1"
             }
    end

    test "omits correlation and causation attributes when absent" do
      assert {:ok, _user} =
               Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{
                 assigns: %{trail: []}
               })

      assert_receive {:span, span(attributes: attributes)}, 1000

      refute Map.has_key?(:otel_attributes.map(attributes), :"messaging.message.conversation_id")
      refute Map.has_key?(:otel_attributes.map(attributes), :"trogon_dispatcher.correlation_id")
      refute Map.has_key?(:otel_attributes.map(attributes), :"trogon_dispatcher.causation_id")
    end
  end

  describe "returned error" do
    test "sets an error status and the error.type attribute" do
      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == ":nope"
      assert :otel_attributes.map(attributes)[:"error.type"] == ":nope"
    end

    test "counts a middleware short circuit as a returned error" do
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{
        actor: :forbidden
      })

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == ":unauthorized"
      assert :otel_attributes.map(attributes)[:"error.type"] == ":unauthorized"
    end

    test "error_status callback can leave the status unset" do
      OpenTelemetryCase.detach_handlers()

      DispatcherOpenTelemetry.setup(error_status: fn _event_name, _measurements, _metadata, _config -> :unset end)

      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:span, span(status: status)}, 1000
      assert status == {:status, :unset, ""}
    end

    test "error_status callback returning nil leaves the span status untouched" do
      OpenTelemetryCase.detach_handlers()

      DispatcherOpenTelemetry.setup(error_status: fn _event_name, _measurements, _metadata, _config -> nil end)

      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, %DispatchOptions{assigns: %{trail: []}})

      assert_receive {:span, span(status: status)}, 1000
      assert status == :undefined
    end
  end

  describe "exceptions" do
    test "records the exception, sets error.type and an error status" do
      assert_raise RuntimeError, "boom", fn ->
        Support.RootDispatcher.dispatch_message(%Support.ExplodingCommand{}, %DispatchOptions{assigns: %{trail: []}})
      end

      assert_receive {:span,
                      span(
                        status: {:status, :error, message},
                        attributes: attributes,
                        events: events
                      )},
                     1000

      assert message == "** (RuntimeError) boom"
      assert :otel_attributes.map(attributes)[:"error.type"] == "RuntimeError"
      assert :otel_attributes.map(attributes)[:"erlang.exception.kind"] == :error

      assert Enum.any?(:otel_events.list(events), &match?(event(name: :exception), &1))
    end
  end

  describe "context propagation" do
    test "the dispatch span is a child of the caller's active span" do
      {parent_trace_id, parent_span_id} =
        Tracer.with_span "caller" do
          ctx = Tracer.current_span_ctx()
          parent_trace_id = :otel_span.trace_id(ctx)
          parent_span_id = :otel_span.span_id(ctx)

          Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, %DispatchOptions{
            assigns: %{trail: []}
          })

          {parent_trace_id, parent_span_id}
        end

      assert_receive {:span, span(trace_id: trace_id, parent_span_id: dispatch_parent_span_id)}, 1000

      assert trace_id == parent_trace_id
      assert dispatch_parent_span_id == parent_span_id
    end
  end

  describe "unregistered messages" do
    test "produce no span" do
      assert {:error, %Trogon.Dispatcher.UnregisteredMessageError{}} =
               Support.RootDispatcher.dispatch_message(%Support.NotRegistered{})

      refute_receive {:span, _span}, 200
    end
  end
end
