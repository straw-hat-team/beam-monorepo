# Trogon.Telemetry

Declare telemetry events as structs.

`:telemetry` carries two loose maps per event, built by hand at every call site and pattern matched by
key on the other side. This package moves that shape into a declaration, so the measurements and the
attributes are structs, the event name lives in one place, and the documentation is generated from what
the code actually emits.

```elixir
defmodule MyApp.Telemetry do
  use Trogon.Telemetry.Catalog, otp_app: :my_app, prefix: [:my_app]
end

defmodule MyApp.Telemetry.LogStreamDelivery do
  @moduledoc "Emitted once per delivery attempt to a log stream destination."

  use MyApp.Telemetry, :event

  event [:hooks, :log_stream_delivery] do
    measurements do
      field :count, :integer, default: 1
    end

    attributes do
      field :project_id, MyApp.ProjectId, tag: true
      field :result, {:enum, [:ok, :error]}, tag: true
    end
  end
end

Trogon.Telemetry.execute(%MyApp.Telemetry.LogStreamDelivery{
  attributes: %MyApp.Telemetry.LogStreamDelivery.Attributes{project_id: project_id, result: :ok}
})
```

`:telemetry` stays the transport, so anything already attached keeps working and reads plain maps.

## Spans

A span wraps a function and emits the `start`, `stop` and `exception` events `:telemetry.span/3` defines.
The measurements and attributes `:telemetry` fills in for you are declared for you too, so `duration`,
`monotonic_time` and the span context show up in the generated documentation without being written out.

```elixir
defmodule MyApp.Telemetry.DeliverLogStream do
  use MyApp.Telemetry, :span

  span [:hooks, :deliver_log_stream] do
    measurements do
      field :bytes_sent, :integer, metric: :histogram, unit: :byte
    end

    attributes do
      field :project_id, MyApp.ProjectId, tag: true
      field :result, {:enum, [:ok, :error]}, tag: true, phase: :stop
    end
  end
end

event = %MyApp.Telemetry.DeliverLogStream{
  attributes: %MyApp.Telemetry.DeliverLogStream.Attributes{project_id: project_id}
}

Trogon.Telemetry.span(event, fn ->
  {:ok, put_in(event.attributes.result, :ok)}
end)
```

An attribute belongs to every phase unless it names one. `result` is only known once the work is done,
so it is declared on `:stop`.

### One declaration, three structs

The three events differ in what they can carry, so each one travels as its own struct.

| Event | Struct | Measurements | Attributes |
| --- | --- | --- | --- |
| `[..., :start]` | `DeliverLogStream.Start` | `monotonic_time`, `system_time` | `project_id`, `telemetry_span_context` |
| `[..., :stop]` | `DeliverLogStream.Stop` | `monotonic_time`, `duration`, `bytes_sent` | `project_id`, `result`, `telemetry_span_context` |
| `[..., :exception]` | `DeliverLogStream.Exception` | `monotonic_time`, `duration` | `project_id`, `telemetry_span_context`, `kind`, `reason`, `stacktrace` |

You still author one `DeliverLogStream`, which holds only what you can set. The projection onto the three
is a struct literal generated at compile time, so nothing walks the declaration while the span runs.

A handler then matches the phase by name, and reading a field the phase does not carry is reported at
compile time rather than reaching a dashboard as a `nil`.

```elixir
alias MyApp.Telemetry.DeliverLogStream.Stop

def handle(%Stop{attributes: %Stop.Attributes{} = attributes}, :stop, _config) do
  Logger.info("delivered with #{attributes.result}")
end
```

Alias the phase, not the section. `Measurements` and `Attributes` belong to every event, so aliasing one
of those leaves directly is how two events end up fighting over the same name, and the second alias wins
without a warning. Aliasing the exception phase shadows `Exception` for that module, though a bare struct
has no `message/1`, so the shadow surfaces as a warning the first time anything calls through it.

## Metrics

A measurement can say which instrument it feeds, and `Telemetry.Metrics` definitions are derived from
that declaration.

```elixir
measurements do
  field :count, :integer, default: 1, metric: :counter, unit: :delivery
  field :bytes_sent, :integer, metric: :histogram, unit: {:byte, :kilobyte}, buckets: [1, 10, 100]
end
```

| Metric              | Aggregation                     |
| ------------------- | ------------------------------- |
| `:counter`          | `Telemetry.Metrics.sum/2`       |
| `:up_down_counter`  | `Telemetry.Metrics.sum/2`       |
| `:histogram`        | `Telemetry.Metrics.distribution/2` |
| `:gauge`            | `Telemetry.Metrics.last_value/2` |

Every metric breaks down by the attributes declared with `tag: true`, and a measurement can narrow that
with its own `tags:`. Collect them where your reporter is started:

```elixir
Supervisor.child_spec({TelemetryMetricsPrometheus, metrics: MyApp.Telemetry.metrics()}, [])
```

A span derives one duration metric per phase that carries it, so success latency and failure latency are
separate series. Refine it with `span [:hooks, :deliver], duration: [unit: {:native, :microsecond}]`, or
opt out with `duration: false`.

Deriving rather than declaring matters here. A reporter reaches for a measurement with `measurements[key]`
and reads its tags straight out of the metadata, but the events declared here carry structs whose
attributes hold value objects. Each derived metric is handed a `:measurement` function that reads the
struct and a `:tag_values` function that dumps the tagged attributes down to scalars.

`:telemetry_metrics` is an optional dependency. Add it yourself to use any of this.

## Observations

Events emitted by somebody else, `ecto`, `oban`, `cowboy`, can be described the same way, so they show up
in the same documentation and feed the same metrics collection.

```elixir
defmodule MyApp.Telemetry.EctoQuery do
  use MyApp.Telemetry, :observation

  observe [:my_app, :repo, :query] do
    measurements do
      field :total_time, :integer, metric: :histogram, unit: {:native, :millisecond}
    end

    attributes do
      field :source, :string, tag: true
    end
  end
end
```

The name is taken as given, the catalog prefix is not applied, and nothing is generated to emit it.

## Installation

Add `trogon_telemetry` to your list of dependencies in `mix.exs`. See the latest
version on [Hex](https://hex.pm/packages/trogon_telemetry).

Documentation is available on [HexDocs](https://hexdocs.pm/trogon_telemetry).
