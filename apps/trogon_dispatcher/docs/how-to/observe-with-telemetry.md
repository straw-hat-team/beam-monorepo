# Observe with telemetry

Every registered dispatch is a `:telemetry.span/3`. The library emits `:telemetry` and nothing else, so any backend
works and no vendor is baked in.

## Events

With a dispatcher declared as:

```elixir
use Trogon.Dispatcher, telemetry_prefix: [:my_app, :dispatcher]
```

the events are:

| Event | Measurements | When |
| --- | --- | --- |
| `[:my_app, :dispatcher, :dispatch, :start]` | `:system_time`, `:monotonic_time` | before the first middleware |
| `[:my_app, :dispatcher, :dispatch, :stop]` | `:duration`, `:monotonic_time` | after the pipeline returns |
| `[:my_app, :dispatcher, :dispatch, :exception]` | `:duration`, `:monotonic_time` | when the pipeline raises, throws or exits |

The default prefix is `[:trogon_dispatcher]`. The prefix is the one that belongs to the dispatcher the caller invoked,
so a message reached through a root dispatcher emits under the root's prefix, once.

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
    [:my_app, :dispatcher, :dispatch, :stop],
    [:my_app, :dispatcher, :dispatch, :exception]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)

defmodule MyApp.Telemetry do
  require Logger

  def handle_event([_, _, :dispatch, :stop], %{duration: duration}, metadata, _config) do
    Logger.info("dispatched",
      dispatched_message: inspect(metadata.message),
      kind: metadata.kind,
      boundary: inspect(metadata.registered_by),
      result: metadata.result,
      duration_ms: System.convert_time_unit(duration, :native, :millisecond)
    )
  end

  def handle_event([_, _, :dispatch, :exception], _measurements, metadata, _config) do
    Logger.error("dispatch raised", dispatched_message: inspect(metadata.message), reason: inspect(metadata.reason))
  end
end
```

## OpenTelemetry

`:telemetry` spans map onto OpenTelemetry through `opentelemetry_telemetry`, so tracing is a wiring step in the host
app rather than a dependency of this library:

```elixir
OpentelemetryTelemetry.start_telemetry_span(
  :my_app,
  "dispatch",
  metadata,
  %{kind: :internal}
)
```

Metrics work the same way through `telemetry_metrics`:

```elixir
Telemetry.Metrics.counter("my_app.dispatcher.dispatch.stop.duration",
  tags: [:message, :kind, :registered_by, :result]
)

Telemetry.Metrics.distribution("my_app.dispatcher.dispatch.stop.duration",
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
    attach_telemetry!([:my_app, :dispatcher])
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

`attach_telemetry!/1` detaches on test exit and forwards only events emitted in the calling process, so `async: true`
modules do not see each other's dispatches.

The assertion helpers are macros, so the module must be imported rather than aliased.
