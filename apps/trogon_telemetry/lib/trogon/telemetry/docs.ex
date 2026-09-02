defmodule Trogon.Telemetry.Docs do
  @moduledoc """
  Renders a `Trogon.Telemetry.Definition` as Markdown.

  Every event module gets this appended to its `@moduledoc`, so the event names, the measurements, the
  attributes and the metrics documented for consumers are the ones the code actually emits.
  """

  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.Definition.Field
  alias Trogon.Telemetry.Instrument
  alias Trogon.Telemetry.Type

  @doc """
  The Markdown section describing a definition.
  """
  @spec render(Definition.t()) :: String.t()
  def render(%Definition{} = definition) do
    """
    ## Telemetry

    #{names(definition)}

    ### Measurements

    #{table(definition, :measurements)}

    ### Attributes

    #{table(definition, :attributes)}\
    #{metrics(definition)}\
    """
  end

  defp names(%Definition{kind: :span} = definition) do
    """
    #{Enum.map_join(Definition.emitted(definition), "\n", &phase_name(definition, &1))}

    Each of the three travels as its own struct, so a phase only carries the fields the table below scopes
    to it. The exception event carries the attributes as they were on start.\
    """
  end

  defp names(%Definition{kind: :observation} = definition) do
    """
    `#{inspect(definition.name)}`

    Emitted elsewhere. This module only describes it, so nothing here executes it.\
    """
  end

  defp names(%Definition{} = definition) do
    "`#{inspect(definition.name)}`"
  end

  defp phase_name(definition, {phase, name}) do
    "- `#{inspect(name)}` as `#{inspect(Definition.wire_module(definition, phase))}`"
  end

  defp table(%Definition{} = definition, section) do
    case Map.fetch!(definition, section) do
      [] -> "None."
      fields -> rows(definition.kind, section, fields)
    end
  end

  defp rows(kind, section, fields) do
    header = header(kind, section, fields)

    [
      "| " <> Enum.join(header, " | ") <> " |",
      "| " <> Enum.map_join(header, " | ", fn _column -> "---" end) <> " |"
      | Enum.map(fields, &row(kind, section, fields, &1))
    ]
    |> Enum.join("\n")
  end

  defp header(kind, section, fields) do
    base(kind, section) ++ instrument_columns(section, fields) ++ ["Description"]
  end

  defp base(:span, :measurements), do: ["Name", "Type", "Phases"]
  defp base(:span, :attributes), do: ["Name", "Type", "Tag", "Phases"]
  defp base(:observation, :measurements), do: ["Name", "Type"]
  defp base(_kind, :measurements), do: ["Name", "Type", "Default"]
  defp base(_kind, :attributes), do: ["Name", "Type", "Tag"]

  defp row(kind, section, fields, %Field{} = field) do
    cells = base_cells(kind, section, field) ++ instrument_cells(section, fields, field) ++ [doc(field)]

    "| " <> Enum.join(cells, " | ") <> " |"
  end

  defp base_cells(:span, :measurements, field), do: [name(field), type(field), phases(field)]
  defp base_cells(:span, :attributes, field), do: [name(field), type(field), tag(field), phases(field)]
  defp base_cells(:observation, :measurements, field), do: [name(field), type(field)]
  defp base_cells(_kind, :measurements, field), do: [name(field), type(field), "`#{inspect(field.default)}`"]
  defp base_cells(_kind, :attributes, field), do: [name(field), type(field), tag(field)]

  defp instrument_columns(:measurements, fields) do
    if instrumented?(fields), do: ["Metric", "Unit"], else: []
  end

  defp instrument_columns(:attributes, _fields), do: []

  defp instrument_cells(:measurements, fields, field) do
    if instrumented?(fields), do: [metric(field), unit(field)], else: []
  end

  defp instrument_cells(:attributes, _fields, _field), do: []

  defp instrumented?(fields), do: Enum.any?(fields, & &1.instrument)

  defp metric(%Field{instrument: nil}), do: ""
  defp metric(%Field{instrument: %Instrument{buckets: nil} = instrument}), do: "`#{instrument.kind}`"

  defp metric(%Field{instrument: %Instrument{} = instrument}) do
    "`#{instrument.kind}`, buckets `#{inspect(instrument.buckets, charlists: :as_lists)}`"
  end

  defp unit(%Field{instrument: nil}), do: ""
  defp unit(%Field{instrument: %Instrument{} = instrument}), do: Instrument.unit_to_string(instrument.unit)

  defp metrics(%Definition{} = definition) do
    case Definition.instrumented(definition) do
      [] -> ""
      instrumented -> "\n\n### Metrics\n\n" <> Enum.map_join(instrumented, "\n", &metric_line(definition, &1))
    end
  end

  defp metric_line(definition, {phase, event_name, %Field{instrument: instrument} = field}) do
    "- `#{Enum.join(event_name ++ [field.name], ".")}` as a #{Instrument.aggregation(instrument)}" <>
      broken_down_by(definition, phase, instrument)
  end

  defp broken_down_by(definition, phase, %Instrument{} = instrument) do
    tags = tags_for(definition, phase, instrument)

    case tags do
      [] -> ""
      tags -> ", broken down by " <> Enum.map_join(tags, ", ", &"`#{&1}`")
    end
  end

  defp tags_for(definition, phase, %Instrument{tags: declared}) do
    for %Field{tag: true} = field <- Definition.fields_for(definition, :attributes, phase),
        declared == nil or field.name in declared,
        do: field.name
  end

  defp name(%Field{name: name}), do: "`#{name}`"
  defp type(%Field{type: type}), do: Type.to_string(type)
  defp phases(%Field{phases: phases}), do: Enum.map_join(phases, ", ", &"`#{&1}`")

  defp tag(%Field{tag: true}), do: "yes"
  defp tag(%Field{tag: false}), do: "no"

  defp doc(%Field{doc: nil, reserved: true, authored: true}) do
    "Filled in by `Trogon.Telemetry` unless it is already set."
  end

  defp doc(%Field{doc: nil, reserved: true}), do: "Filled in by `Trogon.Telemetry`."
  defp doc(%Field{doc: nil}), do: ""
  defp doc(%Field{doc: doc}), do: doc
end
