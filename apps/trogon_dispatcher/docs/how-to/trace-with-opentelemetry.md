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
    {:nimble_options, "~> 1.0"},
    {:opentelemetry, "~> 1.0"}
  ]
end
```

`Trogon.Dispatcher.OpenTelemetry` only exists once `opentelemetry_api`, `opentelemetry_telemetry` and
`nimble_options` are loaded. `nimble_options` validates and documents `setup/1`'s options. Add an OpenTelemetry SDK
such as `opentelemetry` (and an exporter) the same way you would for any other app.

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

Every registered dispatch becomes one span, named `"dispatch #{inspect(message)}"`, with `kind: :consumer`. Per the
OpenTelemetry messaging semantic conventions, a `process` operation is a consumer operation, even though dispatch
runs in-process on the caller's own call stack rather than off a queue.

Attributes:

- `messaging.system`: `"trogon_dispatcher"`
- `messaging.operation.name`: `"dispatch"`
- `messaging.operation.type`: `"process"`
- `messaging.destination.name`: the message module, as `inspect/1`
- `messaging.message.id`: the message id, when set. Can be turned off with `opt_out_attrs`.
- `messaging.message.conversation_id`: the correlation id, when set. Can be turned off with `opt_out_attrs`.
- `code.function.name`: the handler's fully qualified `handle_message/2`, for example
  `"MyApp.Handler.handle_message"`. Can be turned off with `opt_out_attrs`.
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
thrown, or exited pipeline sets an error status, records an OpenTelemetry exception event, and sets the
`erlang.exception.kind` attribute to `:error`, `:throw`, or `:exit`. A raise sets `error.type` to the exception
module; a throw or an exit carries no exception, so `error.type` is `"_OTHER"`, the semantic convention's fallback
value, with the class already on `erlang.exception.kind`. An unrecognized returned error shape also falls back to
`error.type` `"_OTHER"`.

## Customizing attributes

`setup/1` accepts `extra_attrs`, a map of attributes added to every dispatch span, and `opt_out_attrs`, a list that
turns off any of the attributes this module sets by default: `messaging.message.id`,
`messaging.message.conversation_id`, and `code.function.name`. An attribute this module sets always wins over an
extra one under the same key:

```elixir
Trogon.Dispatcher.OpenTelemetry.setup(
  extra_attrs: %{"deployment.environment.name": "production"},
  opt_out_attrs: [:"code.function.name"]
)
```

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

Dispatch is synchronous and in-process: the caller's span is already the current span when the dispatch span opens,
so it becomes the parent for free. There is no `traceparent` to carry, because there is no queue or process boundary
to carry it across.
