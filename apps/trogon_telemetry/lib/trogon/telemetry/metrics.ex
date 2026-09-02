defmodule Trogon.Telemetry.Metrics do
  @moduledoc """
  Derives `Telemetry.Metrics` definitions from declared measurements.

      MyApp.Telemetry.metrics()
      |> TelemetryMetricsPrometheus.Core.child_spec()

  Nothing is declared twice. A measurement that says `metric: :counter` already carries its unit, its
  documentation and the attributes it may be broken down by, so the metric is read off the declaration rather
  than written next to it and left to drift.

  ## Why this cannot be hand written

  A `Telemetry.Metrics` reporter reaches for a measurement with `measurements[key]`, and takes its tags
  straight out of the metadata. Events declared here carry structs, not maps, and their attributes hold value
  objects rather than scalars. So every derived metric is given a `:measurement` function that reads the
  struct, and a `:tag_values` function that runs `Trogon.Telemetry.Type.dump/2` over the tagged attributes.
  That is where a value object finally becomes a scalar, at the exporter edge and nowhere earlier.

  ## Naming

  A metric is named after the event carrying it, with the measurement appended. Since a span emits three
  events, a measurement carried by two of them becomes two metrics:

      [:my_app, :hooks, :deliver_log_stream, :stop, :duration]
      [:my_app, :hooks, :deliver_log_stream, :exception, :duration]

  Latency for calls that succeeded and latency for calls that raised are different questions, so they stay
  different series.
  """

  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.Definition.Field
  alias Trogon.Telemetry.Instrument
  alias Trogon.Telemetry.Type

  @doc """
  Every metric declared under a catalog, in the order the events are declared.
  """
  @spec for_catalog(module()) :: [struct()]
  def for_catalog(catalog) when is_atom(catalog) do
    catalog
    |> Trogon.Telemetry.Catalog.definitions()
    |> Enum.flat_map(&for_definition/1)
  end

  @doc """
  Every metric declared by one event, span or observation.
  """
  @spec for_definition(Definition.t()) :: [struct()]
  def for_definition(%Definition{} = definition) do
    ensure_telemetry_metrics!()

    for {phase, event_name, field} <- Definition.instrumented(definition) do
      build(definition, phase, event_name, field)
    end
  end

  defp build(definition, phase, event_name, %Field{instrument: instrument} = field) do
    tagged = tagged(definition, phase, instrument)

    apply(Telemetry.Metrics, Instrument.aggregation(instrument), [
      event_name ++ [field.name],
      [
        event_name: event_name,
        measurement: measurement(field.name),
        description: field.doc,
        tags: Enum.map(tagged, & &1.name),
        tag_values: tag_values(tagged),
        unit: instrument.unit,
        reporter_options: instrument.reporter_options
      ]
    ])
  end

  defp tagged(definition, phase, %Instrument{tags: nil}) do
    for %Field{tag: true} = field <- Definition.fields_for(definition, :attributes, phase), do: field
  end

  defp tagged(definition, phase, %Instrument{tags: names}) do
    for %Field{tag: true} = field <- Definition.fields_for(definition, :attributes, phase),
        field.name in names,
        do: field
  end

  defp measurement(name), do: &Map.get(&1, name)

  defp tag_values(tagged) do
    dumps = for %Field{} = field <- tagged, do: {field.name, field.type}

    fn attributes ->
      Map.new(dumps, fn {name, type} -> {name, Type.dump(type, Map.get(attributes, name))} end)
    end
  end

  defp ensure_telemetry_metrics! do
    unless Code.ensure_loaded?(Telemetry.Metrics) do
      raise ArgumentError,
            "deriving metrics needs :telemetry_metrics, which is an optional dependency. Add " <>
              "{:telemetry_metrics, \"~> 1.0\"} to your deps"
    end

    :ok
  end
end
