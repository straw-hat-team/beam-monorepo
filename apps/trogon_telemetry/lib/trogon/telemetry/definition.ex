defmodule Trogon.Telemetry.Definition do
  @moduledoc """
  The compiled description of an event, a span or an observation.

  Every module built with `Trogon.Telemetry.Event`, `Trogon.Telemetry.Span` or
  `Trogon.Telemetry.Observation` exposes its definition through `__telemetry__/0`. It is the single source
  the emit functions, the handlers, the generated documentation and the metric derivation read from.
  """

  alias Trogon.Telemetry.Definition.Field

  @typedoc """
  What a declaration describes.

  An `:event` is one emitted name, a `:span` is the three names `:telemetry` conventions expect, and an
  `:observation` describes an event emitted by somebody else so metrics can be derived for it.
  """
  @type kind :: :event | :span | :observation

  @type t :: %__MODULE__{
          kind: kind(),
          module: module(),
          catalog: module() | nil,
          name: [atom(), ...],
          measurements_module: module() | nil,
          attributes_module: module() | nil,
          wire: %{Field.phase() => module()},
          start_name: [atom(), ...] | nil,
          stop_name: [atom(), ...] | nil,
          exception_name: [atom(), ...] | nil,
          measurements: [Field.t()],
          attributes: [Field.t()]
        }

  @enforce_keys [:kind, :module, :name]
  defstruct [
    :kind,
    :module,
    :catalog,
    :name,
    :measurements_module,
    :attributes_module,
    :start_name,
    :stop_name,
    :exception_name,
    wire: %{},
    measurements: [],
    attributes: []
  ]

  @doc """
  The `:telemetry` event names emitted for a definition, paired with the phase each one represents.

  A plain event emits a single name. A span emits the three names `:telemetry` conventions expect.
  """
  @spec emitted(t()) :: [{Field.phase(), [atom(), ...]}, ...]
  def emitted(%__MODULE__{kind: :span} = definition) do
    [
      {:start, definition.start_name},
      {:stop, definition.stop_name},
      {:exception, definition.exception_name}
    ]
  end

  def emitted(%__MODULE__{name: name}), do: [{:event, name}]

  @doc """
  The struct a phase travels as.

  Every emitted name has one envelope module holding the measurements and the attributes that phase
  carries. A plain event travels as the declaring module itself, a span travels as one module per phase.
  """
  @spec wire_module(t(), Field.phase()) :: module() | nil
  def wire_module(%__MODULE__{wire: wire}, phase), do: Map.get(wire, phase)

  @doc """
  Whether a declaration owns the event it describes.

  An observation describes somebody else's event, so nothing here emits it and no struct is generated for it.
  """
  @spec owned?(t()) :: boolean()
  def owned?(%__MODULE__{kind: :observation}), do: false
  def owned?(%__MODULE__{}), do: true

  @doc """
  The attribute names marked with `tag: true`, in declaration order.
  """
  @spec tags(t()) :: [atom()]
  def tags(%__MODULE__{attributes: attributes}) do
    for %Field{tag: true} = field <- attributes, do: field.name
  end

  @doc """
  The fields of a section that are carried by a given phase.
  """
  @spec fields_for(t(), :measurements | :attributes, Field.phase()) :: [Field.t()]
  def fields_for(%__MODULE__{} = definition, section, phase) do
    definition
    |> Map.fetch!(section)
    |> Enum.filter(&(phase in &1.phases))
  end

  @doc """
  The measurements that declared an instrument, paired with the phase carrying them.

  This is what `Trogon.Telemetry.Metrics` walks. A span duration is carried by both the stop and the
  exception event, so it appears once per phase and becomes one metric for each.
  """
  @spec instrumented(t()) :: [{Field.phase(), [atom(), ...], Field.t()}]
  def instrumented(%__MODULE__{} = definition) do
    for {phase, name} <- emitted(definition),
        %Field{instrument: %{}} = field <- fields_for(definition, :measurements, phase),
        do: {phase, name, field}
  end
end
