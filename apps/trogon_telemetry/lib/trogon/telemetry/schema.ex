defmodule Trogon.Telemetry.Schema do
  @moduledoc """
  The declaration blocks shared by `Trogon.Telemetry.Event`, `Trogon.Telemetry.Span` and
  `Trogon.Telemetry.Observation`.

  `:telemetry` carries two maps per event, so a declaration has two sections. `measurements/1` holds the
  numbers, `attributes/1` holds everything describing what happened. Each section is compiled into its own
  struct, and the module itself becomes the envelope holding both.
  """

  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.Definition.Field
  alias Trogon.Telemetry.Docs
  alias Trogon.Telemetry.Instrument
  alias Trogon.Telemetry.Type

  @span_phases [:start, :stop, :exception]

  @reserved_span_measurements [
    {:system_time, :integer, [:start], false},
    {:monotonic_time, :integer, @span_phases, false},
    {:duration, :integer, [:stop, :exception], false}
  ]

  @reserved_span_attributes [
    {:telemetry_span_context, :reference, @span_phases, true},
    {:kind, {:enum, [:error, :exit, :throw]}, [:exception], false},
    {:reason, :term, [:exception], false},
    {:stacktrace, :term, [:exception], false}
  ]

  @instrument_opts [:unit, :buckets, :tags, :reporter_options]

  @doc """
  Declares the numbers carried by the event.

  Measurement types must be numeric, because reporters aggregate them.

      measurements do
        field :count, :integer, default: 1, metric: :counter, unit: :delivery
      end

  Spans do not declare `duration`, `monotonic_time` or `system_time`. Those are filled in by
  `Trogon.Telemetry.span/2` and documented for you. Anything a span does declare is carried by the stop
  event only, since the function never returned on the exception path.
  """
  @spec measurements(Macro.t()) :: Macro.t()
  defmacro measurements(do: block) do
    quote do
      Trogon.Telemetry.Schema.__open__(__MODULE__, :measurements)
      unquote(block)
      Trogon.Telemetry.Schema.__close__(__MODULE__)
    end
  end

  @doc """
  Declares what describes the event.

      attributes do
        field :project_id, MyApp.ProjectId, tag: true
        field :result, {:enum, [:ok, :error]}, tag: true, phase: :stop
      end

  Fields marked `tag: true` are the ones safe to break a metric down by, so cardinality stays bounded.
  """
  @spec attributes(Macro.t()) :: Macro.t()
  defmacro attributes(do: block) do
    quote do
      Trogon.Telemetry.Schema.__open__(__MODULE__, :attributes)
      unquote(block)
      Trogon.Telemetry.Schema.__close__(__MODULE__)
    end
  end

  @doc """
  Declares one field of the surrounding section.

  ## Options

  - `:default` - the value the generated struct starts with.
  - `:doc` - what the field means, rendered into the generated documentation and used as the metric
    description.
  - `:tag` - whether a metric may be broken down by this attribute. Attributes only.
  - `:phase` - which of a span's three events carry this attribute. Spans only, defaults to all three.

  ## Metric options

  Measurements may declare the metric they feed. See `Trogon.Telemetry.Instrument`.

  - `:metric` - the instrument kind, one of `:counter`, `:up_down_counter`, `:histogram` or `:gauge`.
  - `:unit` - the unit of the recorded number, or a `{from, to}` pair to convert on the way out.
  - `:buckets` - advisory histogram boundaries. Histograms only.
  - `:tags` - the attributes to break this metric down by, defaulting to every attribute marked `tag: true`.
  - `:reporter_options` - passed through to `Telemetry.Metrics` untouched.
  """
  @spec field(atom(), Type.t(), keyword()) :: Macro.t()
  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      Trogon.Telemetry.Schema.__field__(__MODULE__, name, type, opts)
    end
  end

  @doc false
  @spec __setup__(module(), Definition.kind(), module() | nil) :: :ok
  def __setup__(module, kind, catalog) do
    Module.register_attribute(module, :trogon_telemetry_measurements, accumulate: true)
    Module.register_attribute(module, :trogon_telemetry_attributes, accumulate: true)
    Module.put_attribute(module, :trogon_telemetry_kind, kind)
    Module.put_attribute(module, :trogon_telemetry_catalog, catalog)
    :ok
  end

  @doc false
  @spec __name__(module(), term()) :: :ok
  def __name__(module, name) do
    unless valid_name?(name) do
      raise ArgumentError, "the event name must be a non-empty list of atoms, got: #{inspect(name)}"
    end

    if Module.get_attribute(module, :trogon_telemetry_name) do
      raise ArgumentError, "#{inspect(module)} already declares an event"
    end

    Module.put_attribute(module, :trogon_telemetry_name, prefixed(module, name))
    :ok
  end

  @doc false
  @spec __span__(module(), keyword()) :: :ok
  def __span__(module, opts) do
    opts = Keyword.validate!(opts, duration: [])
    Module.put_attribute(module, :trogon_telemetry_duration, opts[:duration])
    :ok
  end

  @doc false
  @spec __open__(module(), :measurements | :attributes) :: :ok
  def __open__(module, section) do
    if Module.get_attribute(module, :trogon_telemetry_section) do
      raise ArgumentError, "measurements/1 and attributes/1 cannot be nested"
    end

    Module.put_attribute(module, :trogon_telemetry_section, section)
    :ok
  end

  @doc false
  @spec __close__(module()) :: :ok
  def __close__(module) do
    Module.delete_attribute(module, :trogon_telemetry_section)
    :ok
  end

  @doc false
  @spec __field__(module(), atom(), Type.t(), keyword()) :: :ok
  def __field__(module, name, type, opts) do
    section = section!(module)
    kind = Module.get_attribute(module, :trogon_telemetry_kind)
    opts = Keyword.validate!(opts, [:default, :doc, :phase, :metric] ++ @instrument_opts ++ [tag: false])

    validate_name!(module, section, kind, name)
    validate_type!(section, name, type)
    validate_tag!(section, name, opts[:tag])
    validate_default!(kind, name, opts)

    field = %Field{
      name: name,
      type: type,
      default: opts[:default],
      doc: opts[:doc],
      tag: opts[:tag],
      phases: phases!(kind, section, name, opts[:phase]),
      instrument: instrument!(section, name, opts)
    }

    Module.put_attribute(module, :"trogon_telemetry_#{section}", field)
    :ok
  end

  @doc false
  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(env) do
    module = env.module
    kind = Module.get_attribute(module, :trogon_telemetry_kind)
    name = Module.get_attribute(module, :trogon_telemetry_name) || missing_declaration!(module, kind)

    definition = %Definition{
      kind: kind,
      module: module,
      catalog: Module.get_attribute(module, :trogon_telemetry_catalog),
      name: name,
      measurements_module: section_module(kind, module, Measurements),
      attributes_module: section_module(kind, module, Attributes),
      wire: wire_modules(kind, module),
      start_name: span_name(kind, name, :start),
      stop_name: span_name(kind, name, :stop),
      exception_name: span_name(kind, name, :exception),
      measurements: declared(module, :measurements) ++ instrumented_reserved(module, kind),
      attributes: declared(module, :attributes) ++ reserved(kind, :attributes)
    }

    validate_instrument_tags!(definition)
    put_moduledoc(module, definition, env.line)

    quote do
      unquote(envelope(definition))

      @doc false
      @spec __telemetry__() :: Trogon.Telemetry.Definition.t()
      def __telemetry__, do: unquote(Macro.escape(definition))
    end
  end

  defp instrumented_reserved(module, kind) do
    instrument = duration_instrument!(module, kind)

    for %Field{} = field <- reserved(kind, :measurements) do
      if field.name == :duration, do: %Field{field | instrument: instrument}, else: field
    end
  end

  defp duration_instrument!(_module, kind) when kind != :span, do: nil

  defp duration_instrument!(module, :span) do
    case Module.get_attribute(module, :trogon_telemetry_duration) do
      false ->
        nil

      opts when is_list(opts) ->
        opts = Keyword.validate!(opts, [:metric, :doc] ++ @instrument_opts)
        build_instrument!(:duration, opts[:metric] || :histogram, Keyword.put_new(opts, :unit, {:native, :millisecond}))

      other ->
        raise ArgumentError, ":duration must be a keyword list of metric options or false, got: #{inspect(other)}"
    end
  end

  defp envelope(%Definition{kind: :observation}), do: nil

  defp envelope(%Definition{kind: :event} = definition) do
    quote do
      unquote(sections(definition.module, definition, definition.measurements, definition.attributes))
      unquote(envelope_struct(definition, definition.measurements, definition.attributes))
    end
  end

  defp envelope(%Definition{kind: :span} = definition) do
    measurements = Enum.filter(definition.measurements, & &1.authored)
    attributes = Enum.filter(definition.attributes, & &1.authored)

    quote do
      unquote(sections(definition.module, definition, measurements, attributes))
      unquote(envelope_struct(definition, measurements, attributes))
      unquote_splicing(Enum.map(@span_phases, &phase_envelope(definition, &1)))
      unquote(emitters(definition))
    end
  end

  defp sections(owner, %Definition{} = definition, measurements, attributes) do
    quote do
      defmodule unquote(definition.measurements_module) do
        @moduledoc unquote("Measurements carried by `#{inspect(owner)}`.")
        defstruct unquote(Macro.escape(struct_fields(measurements)))
        @type t :: %__MODULE__{}
      end

      defmodule unquote(definition.attributes_module) do
        @moduledoc unquote("Attributes carried by `#{inspect(owner)}`.")
        defstruct unquote(Macro.escape(struct_fields(attributes)))
        @type t :: %__MODULE__{}
      end
    end
  end

  defp envelope_struct(%Definition{} = definition, measurements, attributes) do
    quote do
      defstruct measurements: unquote(empty_struct(definition.measurements_module, measurements)),
                attributes: unquote(empty_struct(definition.attributes_module, attributes))

      @type t :: %__MODULE__{
              measurements: unquote(definition.measurements_module).t(),
              attributes: unquote(definition.attributes_module).t()
            }
    end
  end

  defp phase_envelope(%Definition{} = definition, phase) do
    module = Definition.wire_module(definition, phase)
    measurements = Definition.fields_for(definition, :measurements, phase)
    attributes = Definition.fields_for(definition, :attributes, phase)

    scoped = %Definition{
      definition
      | measurements_module: Module.concat(module, Measurements),
        attributes_module: Module.concat(module, Attributes)
    }

    moduledoc =
      "The `#{phase}` event of `#{inspect(definition.module)}`, as it reaches a handler. " <>
        "`Trogon.Telemetry.span/2` builds it, so only the fields that phase carries are here."

    quote do
      defmodule unquote(module) do
        @moduledoc unquote(moduledoc)

        unquote(sections(module, scoped, measurements, attributes))
        unquote(envelope_struct(scoped, measurements, attributes))
      end
    end
  end

  defp emitters(%Definition{} = definition) do
    quote do
      @doc false
      @spec __emit_start__(t(), reference(), integer(), integer()) :: :ok
      def __emit_start__(
            %__MODULE__{
              measurements: unquote(source(definition, :measurements, :start)),
              attributes: unquote(source(definition, :attributes, :start))
            },
            telemetry_span_context,
            monotonic_time,
            system_time
          ) do
        :telemetry.execute(
          unquote(definition.start_name),
          unquote(wire_struct(definition, :measurements, :start)),
          unquote(wire_struct(definition, :attributes, :start))
        )
      end

      @doc false
      @spec __emit_stop__(t(), reference(), integer(), integer()) :: :ok
      def __emit_stop__(
            %__MODULE__{
              measurements: unquote(source(definition, :measurements, :stop)),
              attributes: unquote(source(definition, :attributes, :stop))
            },
            telemetry_span_context,
            monotonic_time,
            duration
          ) do
        :telemetry.execute(
          unquote(definition.stop_name),
          unquote(wire_struct(definition, :measurements, :stop)),
          unquote(wire_struct(definition, :attributes, :stop))
        )
      end

      @doc false
      @spec __emit_exception__(
              t(),
              reference(),
              integer(),
              integer(),
              :error | :exit | :throw,
              term(),
              Exception.stacktrace()
            ) :: :ok
      def __emit_exception__(
            %__MODULE__{
              measurements: unquote(source(definition, :measurements, :exception)),
              attributes: unquote(source(definition, :attributes, :exception))
            },
            telemetry_span_context,
            monotonic_time,
            duration,
            kind,
            reason,
            stacktrace
          ) do
        :telemetry.execute(
          unquote(definition.exception_name),
          unquote(wire_struct(definition, :measurements, :exception)),
          unquote(wire_struct(definition, :attributes, :exception))
        )
      end
    end
  end

  defp source(%Definition{} = definition, section, phase) do
    if Enum.any?(Definition.fields_for(definition, section, phase), &(not &1.reserved)) do
      Macro.var(section, __MODULE__)
    else
      Macro.var(:"_#{section}", __MODULE__)
    end
  end

  defp wire_struct(%Definition{} = definition, section, phase) do
    module = Module.concat(Definition.wire_module(definition, phase), Macro.camelize(Atom.to_string(section)))
    source = Macro.var(section, __MODULE__)

    pairs =
      for %Field{name: name} = field <- Definition.fields_for(definition, section, phase) do
        {name,
         if(field.reserved, do: Macro.var(name, __MODULE__), else: {{:., [], [source, name]}, [no_parens: true], []})}
      end

    quote do
      %unquote(module){unquote_splicing(pairs)}
    end
  end

  defp wire_modules(:event, module), do: %{event: module}
  defp wire_modules(:observation, _module), do: %{}

  defp wire_modules(:span, module) do
    Map.new(@span_phases, &{&1, Module.concat(module, Macro.camelize(Atom.to_string(&1)))})
  end

  defp section_module(:observation, _module, _section), do: nil
  defp section_module(_kind, module, section), do: Module.concat(module, section)

  defp section!(module) do
    Module.get_attribute(module, :trogon_telemetry_section) ||
      raise ArgumentError, "field/3 must be called inside a measurements/1 or attributes/1 block"
  end

  defp validate_name!(module, section, kind, name) do
    unless is_atom(name) do
      raise ArgumentError, "a field name must be an atom, got: #{inspect(name)}"
    end

    if name in Enum.map(reserved(kind, section), & &1.name) do
      raise ArgumentError, "#{inspect(name)} is reserved by #{kind} #{section} and is documented for you"
    end

    if name in Enum.map(declared(module, section), & &1.name) do
      raise ArgumentError, "#{inspect(name)} is already declared in #{section}"
    end
  end

  defp validate_type!(section, name, type) do
    unless Type.valid?(type) do
      raise ArgumentError, "unknown type #{inspect(type)} for field #{inspect(name)}"
    end

    if section == :measurements and not Type.numeric?(type) do
      raise ArgumentError,
            "measurement #{inspect(name)} must be numeric, got: #{inspect(type)}. Reporters aggregate " <>
              "measurements, so anything else belongs in attributes/1"
    end
  end

  defp validate_tag!(:measurements, name, true) do
    raise ArgumentError, "measurement #{inspect(name)} cannot be tagged, only attributes can"
  end

  defp validate_tag!(_section, _name, _tag), do: :ok

  defp validate_default!(:observation, name, opts) do
    if Keyword.has_key?(opts, :default) do
      raise ArgumentError,
            "#{inspect(name)} cannot declare a default, an observation describes an event emitted elsewhere"
    end
  end

  defp validate_default!(_kind, _name, _opts), do: :ok

  defp instrument!(section, name, opts) do
    declared = Keyword.take(opts, @instrument_opts)

    case {opts[:metric], declared} do
      {nil, []} ->
        nil

      {nil, [{option, _value} | _rest]} ->
        raise ArgumentError, "#{inspect(name)} declares #{inspect(option)} without a :metric to apply it to"

      {_kind, _declared} when section == :attributes ->
        raise ArgumentError, "attribute #{inspect(name)} cannot declare a :metric, only measurements can"

      {kind, _declared} ->
        build_instrument!(name, kind, opts)
    end
  end

  defp build_instrument!(name, kind, opts) do
    unless Instrument.kind?(kind) do
      raise ArgumentError,
            "unknown metric #{inspect(kind)} for measurement #{inspect(name)}, expected one of " <>
              Enum.map_join(Instrument.kinds(), ", ", &inspect/1)
    end

    %Instrument{
      kind: kind,
      unit: opts[:unit] || :unit,
      buckets: buckets!(name, kind, opts[:buckets]),
      tags: opts[:tags],
      reporter_options: opts[:reporter_options] || []
    }
  end

  defp buckets!(_name, _kind, nil), do: nil

  defp buckets!(name, kind, _buckets) when kind != :histogram do
    raise ArgumentError, "#{inspect(name)} declares :buckets, which only a :histogram takes"
  end

  defp buckets!(_name, :histogram, buckets) do
    unless is_list(buckets) and buckets != [] and Enum.all?(buckets, &is_number/1) do
      raise ArgumentError, ":buckets must be a non-empty list of numbers, got: #{inspect(buckets)}"
    end

    buckets
  end

  defp validate_instrument_tags!(%Definition{} = definition) do
    tags = Definition.tags(definition)

    for %Field{instrument: %Instrument{tags: declared}} = field <- definition.measurements, declared != nil do
      case declared -- tags do
        [] ->
          :ok

        unknown ->
          raise ArgumentError,
                "#{inspect(field.name)} breaks down by #{inspect(unknown)}, which is not declared with " <>
                  "tag: true in attributes/1"
      end
    end

    :ok
  end

  defp phases!(:span, :measurements, _name, nil), do: [:stop]

  defp phases!(:span, :measurements, name, _phase) do
    raise ArgumentError,
          "span measurement #{inspect(name)} cannot declare a phase, it is always carried by the stop event"
  end

  defp phases!(:span, :attributes, _name, nil), do: @span_phases

  defp phases!(:span, :attributes, name, phase) do
    phases = List.wrap(phase)

    case phases -- @span_phases do
      [] -> phases
      unknown -> raise ArgumentError, "unknown phase #{inspect(unknown)} for attribute #{inspect(name)}"
    end
  end

  defp phases!(_kind, _section, _name, nil), do: [:event]

  defp phases!(kind, _section, name, _phase) do
    raise ArgumentError, "#{inspect(name)} cannot declare a phase, only spans have phases, not #{kind}s"
  end

  defp declared(module, section) do
    module
    |> Module.get_attribute(:"trogon_telemetry_#{section}")
    |> Enum.reverse()
  end

  defp reserved(:span, :measurements), do: build_reserved(@reserved_span_measurements)
  defp reserved(:span, :attributes), do: build_reserved(@reserved_span_attributes)
  defp reserved(_kind, _section), do: []

  defp build_reserved(specs) do
    for {name, type, phases, authored} <- specs do
      %Field{name: name, type: type, phases: phases, reserved: true, authored: authored}
    end
  end

  defp struct_fields(fields), do: Enum.map(fields, &{&1.name, &1.default})

  defp empty_struct(module, fields) do
    Macro.escape(Map.new([{:__struct__, module} | struct_fields(fields)]))
  end

  defp span_name(:span, name, phase), do: name ++ [phase]
  defp span_name(_kind, _name, _phase), do: nil

  defp valid_name?(name), do: is_list(name) and name != [] and Enum.all?(name, &is_atom/1)

  defp prefixed(module, name) do
    catalog = Module.get_attribute(module, :trogon_telemetry_catalog)
    kind = Module.get_attribute(module, :trogon_telemetry_kind)

    if catalog && kind != :observation do
      catalog_prefix(catalog) ++ name
    else
      name
    end
  end

  defp catalog_prefix(catalog) do
    Code.ensure_compiled!(catalog)
    catalog.__trogon_telemetry_catalog__().prefix
  end

  defp missing_declaration!(module, kind) do
    raise ArgumentError, "#{inspect(module)} uses Trogon.Telemetry.#{kind_name(kind)} without calling #{kind}/2"
  end

  defp kind_name(:event), do: "Event"
  defp kind_name(:span), do: "Span"
  defp kind_name(:observation), do: "Observation"

  defp put_moduledoc(module, definition, line) do
    case Module.get_attribute(module, :moduledoc) do
      {_line, false} -> :ok
      false -> :ok
      nil -> Module.put_attribute(module, :moduledoc, {line, Docs.render(definition)})
      {doc_line, doc} -> Module.put_attribute(module, :moduledoc, {doc_line, doc <> "\n\n" <> Docs.render(definition)})
    end
  end
end
