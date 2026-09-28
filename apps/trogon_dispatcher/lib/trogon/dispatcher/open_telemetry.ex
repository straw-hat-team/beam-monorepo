if Code.ensure_loaded?(OpentelemetryTelemetry) and Code.ensure_loaded?(NimbleOptions) do
  defmodule Trogon.Dispatcher.OpenTelemetry do
    @moduledoc """
    Optional OpenTelemetry integration for `Trogon.Dispatcher`.

    This module only exists when `:opentelemetry_api`, `:opentelemetry_telemetry` and `:nimble_options` are
    dependencies of the host app; nothing in this library requires them.

    ## Usage

    Call `setup/1` once, in your application's `start/2`:

        defmodule MyApp.Application do
          use Application

          def start(_type, _args) do
            Trogon.Dispatcher.OpenTelemetry.setup()
          end
        end

    ## Trace context propagation

    Dispatch is synchronous and runs in the caller's process, so the OpenTelemetry context already flows from
    caller to handler without any middleware: the dispatch span is naturally a child of whatever span the caller has
    open. There is nothing to propagate.

    ## Span attributes

    Every registered dispatch becomes one span, named `"dispatch \#{inspect(message)}"`, with `kind: :consumer`.
    Per the OpenTelemetry messaging semantic conventions, a `process` operation is a consumer operation, even
    though dispatch runs in-process on the caller's own call stack rather than off a queue.

      * `messaging.system` - `"trogon_dispatcher"`
      * `messaging.operation.name` - `"dispatch"`
      * `messaging.operation.type` - `"process"`
      * `messaging.destination.name` - the message module, as `inspect/1`
      * `messaging.message.id` - the message id, when set. Can be turned off with `opt_out_attrs`.
      * `messaging.message.conversation_id` - the correlation id, when set. Can be turned off with `opt_out_attrs`.
      * `code.function.name` - the handler's fully qualified `handle_message/2`. Can be turned off with
        `opt_out_attrs`.
      * `trogon_dispatcher.*` - see `Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes` for each attribute.

    The actor and the message payload never end up on the span: they are not safe to export to a tracing backend
    by default.

    ## Error mapping

    A returned `{:error, reason}` sets an error status and an `error.type` attribute derived from `reason`. A
    raised, thrown, or exited pipeline sets an error status, records an OpenTelemetry exception event, and sets
    the `erlang.exception.kind` attribute to `:error`, `:throw`, or `:exit`. A raise sets `error.type` to the
    exception module; a throw or an exit carries no exception, so `error.type` is `"_OTHER"`, the semantic
    convention's fallback value, with the class already on `erlang.exception.kind`. An unrecognized returned error
    shape also falls back to `error.type` `"_OTHER"`.

    ## Hook

    The `hook` option runs your own code against the dispatch span, for cases the options above cannot cover, such
    as marking a particular returned error as not an error, or adding an attribute this module has no knowledge of.

        Trogon.Dispatcher.OpenTelemetry.setup(hook: &MyApp.Tracing.dispatch_hook/1)

        def dispatch_hook(%{phase: :stop, meta: %{error: :not_found}, span_ctx: span_ctx}) do
          OpenTelemetry.Span.set_status(span_ctx, OpenTelemetry.status(:ok))
        end

        def dispatch_hook(_context), do: :ok

    The hook is called with a context map: `:event`, `:phase` (`:start` or `:stop`), `:meta`, `:measurements`,
    `:config`, and `:span_ctx`. `:meta` holds the raw `:telemetry` metadata for the phase: on `:start` it is the
    dispatch metadata; on `:stop` it adds `:result` and, on failure, `:error`; an exception also reports as phase
    `:stop`, with `:meta` adding `:kind`, `:reason`, and `:stacktrace` instead.

    A status the hook sets wins over the one this module sets, because the OpenTelemetry SDK keeps the first error
    status and treats an ok status as final. An attribute the hook sets overwrites this module's own attribute
    under the same key, since the hook runs after this module sets its attributes, so namespace your attributes
    (for example `com.acme.*`) rather than reusing a key this module owns. The hook runs after the span already
    exists, so it has no way to influence head sampling.

    On `:start` the hook runs once the span is started and current. On `:stop` it runs after this module sets its
    attributes and before it sets the status. Its return value is ignored.
    """

    alias OpenTelemetry.Span
    alias Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes
    alias Trogon.Dispatcher.OpenTelemetry.SemConv

    @tracer_id __MODULE__
    @telemetry_event [:trogon_dispatcher, :dispatch]
    @events for phase <- [:start, :stop, :exception], do: @telemetry_event ++ [phase]

    @options_schema NimbleOptions.new!(
                      hook: [
                        type: {:or, [nil, {:fun, 1}]},
                        default: nil,
                        doc: """
                        A 1-arity function that receives a context map on each dispatch span's `:start` and `:stop`.
                        See the "Hook" section of the moduledoc for the map, the timing, and an example. A raising, throwing, or
                        exiting hook is ignored and reported through the `[:trogon_dispatcher, :open_telemetry, :warning]`
                        telemetry event, so it cannot detach the handler.

                        Experimental: the context map may change while the hook design in
                        [opentelemetry-erlang-contrib#814](https://github.com/open-telemetry/opentelemetry-erlang-contrib/pull/814)
                        is settled.
                        """
                      ],
                      extra_attrs: [
                        type: :map,
                        default: %{},
                        doc: """
                        Extra span attributes added to every dispatch span. An attribute this module already sets
                        wins over an extra one under the same key.
                        """
                      ],
                      opt_out_attrs: [
                        type:
                          {:list,
                           {:in,
                            [
                              SemConv.messaging_message_id(),
                              SemConv.messaging_message_conversation_id(),
                              SemConv.code_function_name()
                            ]}},
                        default: [],
                        doc: """
                        Attributes this module sets by default that a span should leave off:
                        `messaging.message.id`, `messaging.message.conversation_id`, `code.function.name`.
                        """
                      ]
                    )

    @doc """
    Attaches telemetry handlers that turn dispatch spans into OpenTelemetry spans.

    Call once, typically from `Application.start/2`. Calling it twice raises `MatchError`, since the handler id is
    already attached.

    ## Options

    #{NimbleOptions.docs(@options_schema)}

    ## Example

        Trogon.Dispatcher.OpenTelemetry.setup()

        Trogon.Dispatcher.OpenTelemetry.setup(hook: &MyApp.Tracing.dispatch_hook/1)
    """
    @spec setup(keyword()) :: :ok
    def setup(opts \\ []) do
      config = NimbleOptions.validate!(opts, @options_schema)

      :ok = :telemetry.attach_many({__MODULE__, :dispatch}, @events, &__MODULE__.handle_telemetry_event/4, config)
    end

    @doc false
    def handle_telemetry_event(event, measurements, metadata, config)

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :start] = event, measurements, metadata, config) do
      destination_name = inspect(metadata.message)
      context = metadata.context
      opt_out_attrs = Keyword.fetch!(config, :opt_out_attrs)

      attributes =
        [
          {SemConv.messaging_system(), "trogon_dispatcher"},
          {SemConv.messaging_operation_name(), "dispatch"},
          {SemConv.messaging_operation_type(), "process"},
          {SemConv.messaging_destination_name(), destination_name},
          {DispatcherAttributes.trogon_dispatcher_message(), destination_name},
          {DispatcherAttributes.trogon_dispatcher_kind(), Atom.to_string(metadata.kind)},
          {DispatcherAttributes.trogon_dispatcher_dispatcher(), inspect(metadata.dispatcher)},
          {DispatcherAttributes.trogon_dispatcher_registered_by(), inspect(metadata.registered_by)}
        ]
        |> maybe_add_attribute(
          DispatcherAttributes.trogon_dispatcher_correlation_id(),
          id_attribute(context.correlation_id)
        )
        |> maybe_add_attribute(
          DispatcherAttributes.trogon_dispatcher_causation_id(),
          id_attribute(context.causation_id)
        )
        |> maybe_add_opt_out_attribute(
          SemConv.code_function_name(),
          "#{inspect(metadata.handler)}.handle_message",
          opt_out_attrs
        )
        |> maybe_add_opt_out_attribute(SemConv.messaging_message_id(), id_attribute(context.message_id), opt_out_attrs)
        |> maybe_add_opt_out_attribute(
          SemConv.messaging_message_conversation_id(),
          id_attribute(context.correlation_id),
          opt_out_attrs
        )
        |> add_extra_attrs(Keyword.fetch!(config, :extra_attrs))

      span_ctx =
        OpentelemetryTelemetry.start_telemetry_span(
          @tracer_id,
          "dispatch #{destination_name}",
          metadata,
          %{kind: :consumer, attributes: attributes}
        )

      run_hook(config, event, :start, measurements, metadata, span_ctx)
    end

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :stop] = event, measurements, metadata, config) do
      ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

      with %{result: :error, error: error} <- metadata do
        Span.set_attribute(ctx, SemConv.error_type(), error_type(error))
      end

      run_hook(config, event, :stop, measurements, metadata, ctx)

      with %{result: :error, error: error} <- metadata do
        Span.set_status(ctx, OpenTelemetry.status(:error, format_error(error)))
      end

      OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
    end

    def handle_telemetry_event(
          [:trogon_dispatcher, :dispatch, :exception] = event,
          measurements,
          %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata,
          config
        ) do
      ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

      Span.set_attribute(ctx, SemConv.erlang_exception_kind(), kind)
      record_exception(ctx, Exception.normalize(kind, reason, stacktrace), kind, reason, stacktrace)

      run_hook(config, event, :stop, measurements, metadata, ctx)

      Span.set_status(ctx, OpenTelemetry.status(:error, Exception.format_banner(kind, reason, stacktrace)))

      OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
    end

    defp run_hook(config, event, phase, measurements, metadata, span_ctx) do
      case Keyword.fetch!(config, :hook) do
        nil ->
          :ok

        hook ->
          context = %{
            event: event,
            phase: phase,
            meta: metadata,
            measurements: measurements,
            config: config,
            span_ctx: span_ctx
          }

          try do
            hook.(context)
            :ok
          catch
            kind, reason ->
              :telemetry.execute([:trogon_dispatcher, :open_telemetry, :warning], %{count: 1}, %{
                message: "hook raised, ignoring",
                kind: kind,
                reason: reason,
                stacktrace: __STACKTRACE__
              })

              :ok
          end
      end
    end

    defp record_exception(ctx, exception, _kind, _reason, stacktrace) when is_exception(exception) do
      Span.set_attribute(ctx, SemConv.error_type(), error_type(exception))
      Span.record_exception(ctx, exception, stacktrace)
    end

    defp record_exception(ctx, _normalized, kind, reason, stacktrace) do
      Span.set_attribute(ctx, SemConv.error_type(), "_OTHER")
      :otel_span.record_exception(ctx, kind, reason, stacktrace, [])
    end

    defp maybe_add_attribute(attributes, _key, nil), do: attributes
    defp maybe_add_attribute(attributes, key, value), do: [{key, value} | attributes]

    defp maybe_add_opt_out_attribute(attributes, key, value, opt_out_attrs) do
      if key in opt_out_attrs do
        attributes
      else
        maybe_add_attribute(attributes, key, value)
      end
    end

    defp add_extra_attrs(attributes, extra_attrs) do
      existing_keys = Enum.map(attributes, &elem(&1, 0))
      extra = for {key, value} <- extra_attrs, key not in existing_keys, do: {key, value}

      attributes ++ extra
    end

    defp id_attribute(nil), do: nil
    defp id_attribute(id) when is_binary(id) or is_integer(id) or is_atom(id), do: to_string(id)
    defp id_attribute(_id), do: nil

    defp error_type(error) when is_struct(error), do: inspect(error.__struct__)
    defp error_type(error) when is_atom(error), do: inspect(error)

    defp error_type(error) do
      :telemetry.execute([:trogon_dispatcher, :open_telemetry, :warning], %{count: 1}, %{
        message: "Unknown error type encountered, returning _OTHER",
        error: error
      })

      "_OTHER"
    end

    defp format_error(%{__exception__: true} = exception), do: Exception.message(exception)
    defp format_error(error) when is_binary(error), do: error
    defp format_error(error), do: inspect(error)
  end
end
