# Observe with telemetry

Every registered dispatch is a `:telemetry.span/3`. The library emits `:telemetry` and nothing else, so any backend
works and no vendor is baked in. See the Telemetry section of `Trogon.Dispatcher` for the event names,
measurements and metadata keys.

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

  require Trogon.Dispatcher.Test, as: Test

  setup do
    Test.attach_telemetry!()
    :ok
  end

  test "emits a successful span" do
    assert {:ok, _user} = MyApp.Dispatcher.dispatch_message(%RegisterUser{email: "a@b.c"})

    Test.assert_dispatch_start(RegisterUser)
    metadata = Test.assert_dispatch_stop(RegisterUser)

    assert metadata.result == :ok
    assert metadata.registered_by == MyApp.Accounts.Dispatcher
  end

  test "does not dispatch when the request is rejected" do
    Test.refute_dispatch(RegisterUser)
  end
end
```

See `Trogon.Dispatcher.Test` for what `attach_telemetry!/0` isolates and why the assertion helpers must be
required.
