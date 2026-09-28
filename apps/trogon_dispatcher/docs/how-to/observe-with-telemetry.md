# Observe with telemetry

Every registered dispatch is a `:telemetry.span/3`. The library emits `:telemetry` and nothing else, so any backend
works and no vendor is baked in.

## Events

Every dispatcher emits the same events:

| Event | Measurements | When |
| --- | --- | --- |
| `[:trogon_dispatcher, :dispatch, :start]` | `:system_time`, `:monotonic_time` | before the first middleware |
| `[:trogon_dispatcher, :dispatch, :stop]` | `:duration`, `:monotonic_time` | after the pipeline returns |
| `[:trogon_dispatcher, :dispatch, :exception]` | `:duration`, `:monotonic_time` | when the pipeline raises, throws or exits |

A message reached through a root dispatcher emits once, not once per layer. The event names are the same for every
dispatcher, so tell them apart with the `:dispatcher` and `:registered_by` metadata rather than with the event name.

An unregistered message emits nothing. The catch-all clause returns
`{:error, %Trogon.Dispatcher.UnregisteredMessageError{}}` before the span opens, so a backend that counts `:stop`
events will not see routing failures. Routing is resolved at compile time, which makes an unregistered message a
wiring mistake rather than a runtime outcome worth a metric, but count the error return yourself if you dispatch
structs that come from outside your own code.

## Metadata

Start metadata:

- `:message` is the message module, which is the message name. There is no separate string name.
- `:kind` is `:command` or `:query`.
- `:dispatcher` is the module whose `dispatch_message/2` was called.
- `:registered_by` is the dispatcher that declared the registration, which is the owning boundary.
- `:handler` is the module whose `handle_message/2` runs.
- `:context` is the full `Trogon.Dispatcher.Context`. On `:start` it is the context the pipeline began with; on
  `:stop` it is the context the pipeline finished with, so anything a middleware or the handler assigned is visible
  there, along with `:response`.
- `:telemetry_span_context` is added by `:telemetry.span/3`.

Stop metadata carries all of the above plus:

- `:result`, either `:ok` or `:error`, as a flat dimension so a metric can group on it without unpacking a tuple.
- `:error`, present only when `:result` is `:error`, carrying the error term.

Exception metadata carries `:kind`, `:reason` and `:stacktrace` from `:telemetry.span/3`.

`:dispatcher` and `:registered_by` are separate on purpose. `:dispatcher` answers who was called, `:registered_by`
answers which boundary owns the message, and a dashboard usually wants to group on the second.

## Attach a handler

```elixir
:telemetry.attach_many(
  "my-app-dispatch-logger",
  [
    [:trogon_dispatcher, :dispatch, :stop],
    [:trogon_dispatcher, :dispatch, :exception]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)

defmodule MyApp.Telemetry do
  require Logger

  def handle_event([:trogon_dispatcher, :dispatch, :stop], %{duration: duration}, metadata, _config) do
    Logger.info("dispatched",
      dispatched_message: inspect(metadata.message),
      kind: metadata.kind,
      boundary: inspect(metadata.registered_by),
      result: metadata.result,
      duration_ms: System.convert_time_unit(duration, :native, :millisecond)
    )
  end

  def handle_event([:trogon_dispatcher, :dispatch, :exception], _measurements, metadata, _config) do
    Logger.error("dispatch raised", dispatched_message: inspect(metadata.message), reason: inspect(metadata.reason))
  end
end
```

## OpenTelemetry

For distributed tracing, see [Trace with OpenTelemetry](trace-with-opentelemetry.html): an optional
`Trogon.Dispatcher.OpenTelemetry` module ships with the library and turns the dispatch span into an OpenTelemetry
span once you add the OpenTelemetry deps.

## Metrics

Metrics work the same way through `telemetry_metrics`:

```elixir
Telemetry.Metrics.counter("trogon_dispatcher.dispatch.stop.duration",
  tags: [:message, :kind, :dispatcher, :registered_by, :result]
)

Telemetry.Metrics.distribution("trogon_dispatcher.dispatch.stop.duration",
  unit: {:native, :millisecond},
  tags: [:message, :registered_by]
)
```

## Assert on events in tests

```elixir
defmodule MyApp.DispatcherTest do
  use ExUnit.Case, async: true

  import Trogon.Dispatcher.Test

  setup do
    attach_telemetry!()
    :ok
  end

  test "emits a successful span" do
    assert {:ok, _user} = MyApp.Dispatcher.dispatch_message(%RegisterUser{email: "a@b.c"})

    assert_dispatch_start(RegisterUser)
    metadata = assert_dispatch_stop(RegisterUser)

    assert metadata.result == :ok
    assert metadata.registered_by == MyApp.Accounts.Dispatcher
  end

  test "does not dispatch when the request is rejected" do
    refute_dispatch(RegisterUser)
  end
end
```

`attach_telemetry!/0` detaches on test exit and forwards only events emitted in the calling process, so `async: true`
modules do not see each other's dispatches.

The assertion helpers are macros, so the module must be imported rather than aliased.
