# Trace with OpenTelemetry

`Trogon.Dispatcher` emits `:telemetry` and nothing else, so tracing is an optional integration rather than a
dependency of the library. `Trogon.Dispatcher.OpenTelemetry` bridges the dispatch span onto OpenTelemetry through
`opentelemetry_telemetry`; see its moduledoc for the span shape, the attributes it sets, and how errors map to
span status.

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

`Trogon.Dispatcher.OpenTelemetry` only exists once these are loaded. Add an OpenTelemetry SDK such as
`opentelemetry` (and an exporter) the same way you would for any other app.

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

## Customize attributes

```elixir
Trogon.Dispatcher.OpenTelemetry.setup(
  extra_attrs: %{"deployment.environment.name": "production"},
  opt_out_attrs: [:"code.function.name"]
)
```

## Override the status for a returned error

```elixir
Trogon.Dispatcher.OpenTelemetry.setup(
  error_status: fn
    _event_name, _measurements, %{error: :not_found}, _config -> :unset
    _event_name, _measurements, _metadata, _config -> :error
  end
)
```

See the `setup/1` options documentation on `Trogon.Dispatcher.OpenTelemetry` for what each option defaults to.
