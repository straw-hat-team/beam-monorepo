defmodule Trogon.Dispatcher.OpenTelemetryTest do
  use Trogon.Dispatcher.OpenTelemetryCase, async: false

  alias OpenTelemetry.Span
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.OpenTelemetry, as: DispatcherOpenTelemetry
  alias Trogon.Dispatcher.OpenTelemetryCase
  alias Trogon.Dispatcher.TestSupport, as: Support

  require OpenTelemetry.Tracer, as: Tracer

  doctest Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes

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

    test "rejects an opt_out_attrs entry outside the allowed attribute list" do
      OpenTelemetryCase.detach_handlers()

      assert_raise NimbleOptions.ValidationError, fn ->
        DispatcherOpenTelemetry.setup(opt_out_attrs: [:"messaging.system"])
      end
    end
  end

  describe "successful dispatch" do
    test "starts a span named after the operation and destination, kind consumer, with messaging and code attributes" do
      options =
        DispatchOptions.new!(
          message_id: "msg-1",
          correlation_id: "corr-1",
          causation_id: "cause-1",
          assigns: %{trail: []}
        )

      assert {:ok, _user} = Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(name: name, kind: kind, attributes: attributes)}, 1000

      assert name == "dispatch Trogon.Dispatcher.TestSupport.RegisterUser"
      assert kind == :consumer

      assert :otel_attributes.map(attributes) == %{
               "messaging.system": "trogon_dispatcher",
               "messaging.operation.name": "dispatch",
               "messaging.operation.type": "process",
               "messaging.destination.name": "Trogon.Dispatcher.TestSupport.RegisterUser",
               "messaging.message.id": "msg-1",
               "messaging.message.conversation_id": "corr-1",
               "code.function.name": "Trogon.Dispatcher.TestSupport.RegisterUser.handle_message",
               "trogon_dispatcher.message": "Trogon.Dispatcher.TestSupport.RegisterUser",
               "trogon_dispatcher.kind": "command",
               "trogon_dispatcher.dispatcher": "Trogon.Dispatcher.TestSupport.RootDispatcher",
               "trogon_dispatcher.registered_by": "Trogon.Dispatcher.TestSupport.AccountsDispatcher",
               "trogon_dispatcher.correlation_id": "corr-1",
               "trogon_dispatcher.causation_id": "cause-1"
             }
    end

    test "omits correlation, causation, and messaging id attributes when absent" do
      assert {:ok, _user} =
               Support.RootDispatcher.dispatch_message(
                 %Support.RegisterUser{email: "a@b.c"},
                 DispatchOptions.new!(assigns: %{trail: []})
               )

      assert_receive {:span, span(attributes: attributes)}, 1000

      attributes_map = :otel_attributes.map(attributes)

      refute Map.has_key?(attributes_map, :"messaging.message.id")
      refute Map.has_key?(attributes_map, :"messaging.message.conversation_id")
      refute Map.has_key?(attributes_map, :"trogon_dispatcher.correlation_id")
      refute Map.has_key?(attributes_map, :"trogon_dispatcher.causation_id")
      assert Map.has_key?(attributes_map, :"code.function.name")
    end

    test "reports the kind of a query" do
      Support.RootDispatcher.dispatch_message(%Support.GetUser{id: 1}, DispatchOptions.new!(assigns: %{trail: []}))

      assert_receive {:span, span(name: name, attributes: attributes)}, 1000

      assert name == "dispatch Trogon.Dispatcher.TestSupport.GetUser"
      assert :otel_attributes.map(attributes)[:"trogon_dispatcher.kind"] == "query"
    end

    test "omits id attributes whose value is not a string, integer, or atom" do
      options =
        DispatchOptions.new!(
          message_id: {:uuid, "msg-1"},
          correlation_id: %{id: "corr-1"},
          causation_id: ["cause-1"],
          assigns: %{trail: []}
        )

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(attributes: attributes)}, 1000

      attributes_map = :otel_attributes.map(attributes)

      refute Map.has_key?(attributes_map, :"messaging.message.id")
      refute Map.has_key?(attributes_map, :"messaging.message.conversation_id")
      refute Map.has_key?(attributes_map, :"trogon_dispatcher.correlation_id")
      refute Map.has_key?(attributes_map, :"trogon_dispatcher.causation_id")
    end

    test "turns integer and atom ids into strings" do
      options = DispatchOptions.new!(message_id: 42, correlation_id: :corr, assigns: %{trail: []})

      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(attributes: attributes)}, 1000

      attributes_map = :otel_attributes.map(attributes)

      assert attributes_map[:"messaging.message.id"] == "42"
      assert attributes_map[:"messaging.message.conversation_id"] == "corr"
    end

    test "does not fall back to causation_id for messaging.message.id" do
      options = DispatchOptions.new!(causation_id: "cause-1", assigns: %{trail: []})
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(attributes: attributes)}, 1000

      attributes_map = :otel_attributes.map(attributes)

      refute Map.has_key?(attributes_map, :"messaging.message.id")
      assert attributes_map[:"trogon_dispatcher.causation_id"] == "cause-1"
    end
  end

  describe "returned error" do
    test "sets an error status and the error.type attribute" do
      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, DispatchOptions.new!(assigns: %{trail: []}))

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == ":nope"
      assert :otel_attributes.map(attributes)[:"error.type"] == ":nope"
    end

    test "sets an error status when the reason is falsy" do
      Support.FalsyErrorDispatcher.dispatch_message(%Support.FalsyError{})

      assert_receive {:span, span(status: {:status, :error, "nil"}, attributes: attributes)}, 1000
      assert :otel_attributes.map(attributes)[:"error.type"] == "nil"
    end

    test "falls back to error.type _OTHER for an error reason that is neither a struct nor an atom" do
      Support.UnknownShapeErrorDispatcher.dispatch_message(%Support.UnknownShapeError{})

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert :otel_attributes.map(attributes)[:"error.type"] == "_OTHER"
    end

    test "describes an exception error term with its message and types it by its module" do
      assert {:error, %ArgumentError{}} = Support.ErrorReasonDispatcher.dispatch_message(%Support.ExceptionError{})

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == "bad input"
      assert :otel_attributes.map(attributes)[:"error.type"] == "ArgumentError"
    end

    test "uses a string error term as the status description" do
      assert {:error, "card declined"} = Support.ErrorReasonDispatcher.dispatch_message(%Support.TextError{})

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == "card declined"
      assert :otel_attributes.map(attributes)[:"error.type"] == "_OTHER"
    end

    test "emits a warning event when the error term has no known type" do
      test_pid = self()

      :telemetry.attach(
        "unknown-error-type-warning-test",
        [:trogon_dispatcher, :open_telemetry, :warning],
        fn _event, _measurements, metadata, _config -> send(test_pid, {:warning, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach("unknown-error-type-warning-test") end)

      Support.ErrorReasonDispatcher.dispatch_message(%Support.TextError{})

      assert_receive {:warning, %{message: "Unknown error type encountered, returning _OTHER", error: "card declined"}},
                     1000
    end

    test "counts a middleware short circuit as a returned error" do
      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(actor: :forbidden)
      )

      assert_receive {:span, span(status: {:status, :error, message}, attributes: attributes)}, 1000

      assert message == ":unauthorized"
      assert :otel_attributes.map(attributes)[:"error.type"] == ":unauthorized"
    end
  end

  describe "exceptions" do
    test "records the exception, sets error.type and an error status" do
      assert_raise RuntimeError, "boom", fn ->
        Support.RootDispatcher.dispatch_message(
          %Support.ExplodingCommand{},
          DispatchOptions.new!(assigns: %{trail: []})
        )
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

  describe "throws and exits" do
    test "a thrown pipeline records an exception event and falls back to error.type _OTHER" do
      assert catch_throw(Support.NonRaisingFailureDispatcher.dispatch_message(%Support.Throwing{})) == :boom

      assert_receive {:span, span(status: {:status, :error, _message}, attributes: attributes, events: events)}, 1000

      assert :otel_attributes.map(attributes)[:"error.type"] == "_OTHER"
      assert :otel_attributes.map(attributes)[:"erlang.exception.kind"] == :throw
      assert Enum.any?(:otel_events.list(events), &match?(event(name: :exception), &1))
    end

    test "an exited pipeline records an exception event and falls back to error.type _OTHER" do
      assert catch_exit(Support.NonRaisingFailureDispatcher.dispatch_message(%Support.Exiting{})) == :boom

      assert_receive {:span, span(status: {:status, :error, _message}, attributes: attributes, events: events)}, 1000

      assert :otel_attributes.map(attributes)[:"error.type"] == "_OTHER"
      assert :otel_attributes.map(attributes)[:"erlang.exception.kind"] == :exit
      assert Enum.any?(:otel_events.list(events), &match?(event(name: :exception), &1))
    end
  end

  describe "opt_out_attrs option" do
    test "leaves off messaging.message.id when opted out" do
      OpenTelemetryCase.detach_handlers()
      DispatcherOpenTelemetry.setup(opt_out_attrs: [:"messaging.message.id"])

      options = DispatchOptions.new!(message_id: "msg-1", assigns: %{trail: []})
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(attributes: attributes)}, 1000
      refute Map.has_key?(:otel_attributes.map(attributes), :"messaging.message.id")
    end

    test "leaves off messaging.message.conversation_id when opted out" do
      OpenTelemetryCase.detach_handlers()
      DispatcherOpenTelemetry.setup(opt_out_attrs: [:"messaging.message.conversation_id"])

      options = DispatchOptions.new!(correlation_id: "corr-1", assigns: %{trail: []})
      Support.RootDispatcher.dispatch_message(%Support.RegisterUser{email: "a@b.c"}, options)

      assert_receive {:span, span(attributes: attributes)}, 1000
      refute Map.has_key?(:otel_attributes.map(attributes), :"messaging.message.conversation_id")
    end

    test "leaves off code.function.name when opted out" do
      OpenTelemetryCase.detach_handlers()
      DispatcherOpenTelemetry.setup(opt_out_attrs: [:"code.function.name"])

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:span, span(attributes: attributes)}, 1000
      refute Map.has_key?(:otel_attributes.map(attributes), :"code.function.name")
    end
  end

  describe "extra_attrs option" do
    test "adds extra attributes to every span" do
      OpenTelemetryCase.detach_handlers()
      DispatcherOpenTelemetry.setup(extra_attrs: %{"deployment.environment.name": "test"})

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert :otel_attributes.map(attributes)[:"deployment.environment.name"] == "test"
    end

    test "an attribute this module already sets wins over an extra one under the same key" do
      OpenTelemetryCase.detach_handlers()
      DispatcherOpenTelemetry.setup(extra_attrs: %{"messaging.system": "overridden"})

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert :otel_attributes.map(attributes)[:"messaging.system"] == "trogon_dispatcher"
    end
  end

  describe "hook option" do
    test "start phase receives the context map and can set an attribute on the dispatch span" do
      OpenTelemetryCase.detach_handlers()
      test_pid = self()

      DispatcherOpenTelemetry.setup(
        hook: fn context ->
          send(test_pid, {:hook, context})

          if context.phase == :start do
            Span.set_attribute(context.span_ctx, :"com.acme.hooked", true)
          end
        end
      )

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:hook,
                      %{
                        event: [:trogon_dispatcher, :dispatch, :start],
                        phase: :start,
                        meta: meta,
                        measurements: measurements,
                        config: config,
                        span_ctx: span_ctx
                      }},
                     1000

      assert %Support.RegisterUser{} = meta.message
      assert is_map(measurements)
      assert Keyword.keyword?(config)
      assert span_ctx != :undefined

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert :otel_attributes.map(attributes)[:"com.acme.hooked"] == true
    end

    test "stop phase runs on a successful dispatch" do
      OpenTelemetryCase.detach_handlers()
      test_pid = self()

      DispatcherOpenTelemetry.setup(hook: fn context -> send(test_pid, {:hook, context}) end)

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:hook, %{phase: :start}}, 1000
      assert_receive {:hook, %{event: [:trogon_dispatcher, :dispatch, :stop], phase: :stop, meta: meta}}, 1000
      assert meta.result == :ok
      refute Map.has_key?(meta, :error)
    end

    test "stop phase can set the status to ok on a returned error, and that wins" do
      OpenTelemetryCase.detach_handlers()

      DispatcherOpenTelemetry.setup(
        hook: fn
          %{phase: :stop, meta: %{error: :nope}, span_ctx: span_ctx} ->
            Span.set_status(span_ctx, OpenTelemetry.status(:ok))

          _context ->
            :ok
        end
      )

      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, DispatchOptions.new!(assigns: %{trail: []}))

      assert_receive {:span, span(status: status)}, 1000
      assert status == {:status, :ok, ""}
    end

    test "stop phase setting an error status with a custom description wins over ours" do
      OpenTelemetryCase.detach_handlers()

      DispatcherOpenTelemetry.setup(
        hook: fn
          %{phase: :stop, meta: %{error: :nope}, span_ctx: span_ctx} ->
            Span.set_status(span_ctx, OpenTelemetry.status(:error, "custom description"))

          _context ->
            :ok
        end
      )

      Support.RootDispatcher.dispatch_message(%Support.FailingCommand{}, DispatchOptions.new!(assigns: %{trail: []}))

      assert_receive {:span, span(status: {:status, :error, "custom description"})}, 1000
    end

    test "an exception maps to phase :stop, with kind in meta" do
      OpenTelemetryCase.detach_handlers()
      test_pid = self()

      DispatcherOpenTelemetry.setup(hook: fn context -> send(test_pid, {:hook, context}) end)

      assert_raise RuntimeError, "boom", fn ->
        Support.RootDispatcher.dispatch_message(
          %Support.ExplodingCommand{},
          DispatchOptions.new!(assigns: %{trail: []})
        )
      end

      assert_receive {:hook, %{phase: :start}}, 1000

      assert_receive {:hook,
                      %{
                        event: [:trogon_dispatcher, :dispatch, :exception],
                        phase: :stop,
                        meta: %{kind: :error, reason: reason, stacktrace: stacktrace}
                      }},
                     1000

      assert %RuntimeError{message: "boom"} = reason
      assert is_list(stacktrace)
    end

    test "a raising hook does not detach the handler, and emits the warning event" do
      OpenTelemetryCase.detach_handlers()
      test_pid = self()

      :telemetry.attach(
        "hook-raises-warning-test",
        [:trogon_dispatcher, :open_telemetry, :warning],
        fn _event, _measurements, metadata, _config -> send(test_pid, {:warning, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach("hook-raises-warning-test") end)

      DispatcherOpenTelemetry.setup(hook: fn _context -> raise "boom from hook" end)

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:warning, %{message: "hook raised, ignoring", kind: :error, reason: %RuntimeError{}}}, 1000
      assert_receive {:span, _span}, 1000

      Support.RootDispatcher.dispatch_message(
        %Support.RegisterUser{email: "a@b.c"},
        DispatchOptions.new!(assigns: %{trail: []})
      )

      assert_receive {:span, _span}, 1000
    end
  end

  describe "context propagation" do
    test "the dispatch span is a child of the caller's active span" do
      {parent_trace_id, parent_span_id} =
        Tracer.with_span "caller" do
          ctx = Tracer.current_span_ctx()
          parent_trace_id = :otel_span.trace_id(ctx)
          parent_span_id = :otel_span.span_id(ctx)

          Support.RootDispatcher.dispatch_message(
            %Support.RegisterUser{email: "a@b.c"},
            DispatchOptions.new!(assigns: %{trail: []})
          )

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
