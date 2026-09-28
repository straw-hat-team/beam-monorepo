# Trace with OpenTelemetry

`Trogon.Dispatcher` emits `:telemetry` and nothing else, so tracing is an optional integration rather than a
dependency of the library. `Trogon.Dispatcher.OpenTelemetry` bridges the dispatch span onto OpenTelemetry through
`opentelemetry_telemetry`.

## Add the dependencies

```elixir
def deps do
  [
    {:trogon_dispatcher, "~> 0.1"},
    {:opentelemetry_api, "~> 1.0"},
    {:opentelemetry_telemetry, "~> 1.0"},
    {:opentelemetry, "~> 1.0"}
  ]
end
```

`Trogon.Dispatcher.OpenTelemetry` only exists once `opentelemetry_api` and `opentelemetry_telemetry` are loaded. Add
an OpenTelemetry SDK such as `opentelemetry` (and an exporter) the same way you would for any other app.

## Wire it up

Call `setup/1` once, from your application's `start/2`:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    Trogon.Dispatcher.OpenTelemetry.setup()

    Supervisor.start_link([MyApp.Repo], strategy: :one_for_one)
  end
end
```

Calling `setup/1` twice raises `MatchError`, since the second call tries to attach a handler id that already exists.

## What the span looks like

Every registered dispatch becomes one span, named `"dispatch #{inspect(message)}"`, with `kind: :internal`. Dispatch
runs synchronously in the caller's process, so this is not a consumer or a producer, it is work the caller is doing
inline.

Attributes:

- `messaging.system`: `"trogon_dispatcher"`
- `messaging.operation.name`: `"dispatch"`
- `messaging.operation.type`: `"process"`
- `messaging.destination.name`: the message module, as `inspect/1`
- `messaging.message.conversation_id`: the correlation id, when set
- `trogon_dispatcher.message`: the message module, as `inspect/1`
- `trogon_dispatcher.kind`: `"command"` or `"query"`
- `trogon_dispatcher.dispatcher`: the entry point that was called
- `trogon_dispatcher.registered_by`: the dispatcher that declared the registration
- `trogon_dispatcher.correlation_id`: when set
- `trogon_dispatcher.causation_id`: when set

The `trogon_dispatcher.*` names are exposed as functions on `Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes`, so
code that queries or asserts on spans does not have to repeat the strings.

The actor and the message payload never end up on the span: they are not safe to export to a tracing backend by
default.

A returned `{:error, reason}` sets an error status and an `error.type` attribute derived from `reason`. A raised,
thrown, or exited pipeline sets an error status and the `erlang.exception.kind` attribute. A raise also records an
OpenTelemetry exception event and sets `error.type` to the exception module; a throw or an exit carries no exception,
so `error.type` is `throw` or `exit`.

## Overriding the status for a returned error

Pass `error_status`, a 4-arity function that receives the same arguments as a `:telemetry` handler for the `:stop`
event and returns `:unset`, `:ok`, `:error`, or `nil`:

```elixir
Trogon.Dispatcher.OpenTelemetry.setup(
  error_status: fn
    _event_name, _measurements, %{error: :not_found}, _config -> :unset
    _event_name, _measurements, _metadata, _config -> :error
  end
)
```

Returning `nil` leaves the span status untouched. This callback only runs for a returned `:error`; an exception
always gets OpenTelemetry's exception semantics regardless of this option.

## Why there is no propagation middleware

Dispatch is in-process and synchronous: the handler runs in the same process, on the same call stack, as the code
that called `dispatch_message/2`. There is no queue, no message hop, and no other process to hand a trace context
to. The dispatch span opens while the caller's span is still the current span, so it becomes a child of it for free.
Nothing needs to serialize a `traceparent` and nothing needs to read one back.
