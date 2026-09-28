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

            Supervisor.start_link([MyApp.Repo], strategy: :one_for_one)
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
    """

    alias OpenTelemetry.Span
    alias Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes
    alias Trogon.Dispatcher.OpenTelemetry.SemConv

    @tracer_id __MODULE__
    @telemetry_event [:trogon_dispatcher, :dispatch]
    @events for phase <- [:start, :stop, :exception], do: @telemetry_event ++ [phase]

    @typedoc """
    Callback used to decide the OpenTelemetry span status for a returned `:error` result.

    Only invoked when the `:stop` event carries an `:error`. Exceptions always use OpenTelemetry exception
    semantics and never go through this callback.
    """
    @type error_status_callback ::
            (event_name :: [atom()], measurements :: map(), metadata :: map(), config :: keyword() ->
               :unset | :ok | :error | nil)

    @options_schema NimbleOptions.new!(
                      error_status: [
                        type: {:or, [nil, {:fun, 4}]},
                        default: nil,
                        doc: """
                        A `t:error_status_callback/0` to override the span status set for a returned `:error`.
                        Defaults to always setting an error status. Return `nil` from the callback to leave the
                        status unset.

                        Experimental: this callback shape is expected to change to follow the hook contract proposed
                        in [opentelemetry-erlang-contrib#814](https://github.com/open-telemetry/opentelemetry-erlang-contrib/pull/814).
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

        Trogon.Dispatcher.OpenTelemetry.setup(
          error_status: fn
            _event_name, _measurements, %{error: :not_found}, _config -> :unset
            _event_name, _measurements, _metadata, _config -> :error
          end
        )
    """
    @spec setup(keyword()) :: :ok
    def setup(opts \\ []) do
      config = NimbleOptions.validate!(opts, @options_schema)

      :ok = :telemetry.attach_many({__MODULE__, :dispatch}, @events, &__MODULE__.handle_telemetry_event/4, config)
    end

    @doc false
    def handle_telemetry_event(event, measurements, metadata, config)

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :start], _measurements, metadata, config) do
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

      OpentelemetryTelemetry.start_telemetry_span(
        @tracer_id,
        "dispatch #{destination_name}",
        metadata,
        %{kind: :consumer, attributes: attributes}
      )
    end

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :stop], measurements, metadata, config) do
      ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

      with %{result: :error, error: error} <- metadata do
        Span.set_attribute(ctx, SemConv.error_type(), error_type(error))
        set_error_status(ctx, error, [:trogon_dispatcher, :dispatch, :stop], measurements, metadata, config)
      end

      OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
    end

    def handle_telemetry_event(
          [:trogon_dispatcher, :dispatch, :exception],
          _measurements,
          %{kind: kind, reason: reason, stacktrace: stacktrace} = metadata,
          _config
        ) do
      ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

      Span.set_attribute(ctx, SemConv.erlang_exception_kind(), kind)

      record_exception(ctx, Exception.normalize(kind, reason, stacktrace), kind, reason, stacktrace)
      Span.set_status(ctx, OpenTelemetry.status(:error, Exception.format_banner(kind, reason, stacktrace)))

      OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
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

    defp set_error_status(ctx, error, event_name, measurements, metadata, config) do
      status_code =
        case Keyword.get(config, :error_status) do
          nil -> :error
          fun when is_function(fun, 4) -> fun.(event_name, measurements, metadata, config)
        end

      apply_error_status(ctx, status_code, error)
    end

    defp apply_error_status(_ctx, nil, _error), do: :ok

    defp apply_error_status(ctx, code, _error) when code in [:unset, :ok] do
      Span.set_status(ctx, OpenTelemetry.status(code))
    end

    defp apply_error_status(ctx, :error, error) do
      Span.set_status(ctx, OpenTelemetry.status(:error, format_error(error)))
    end

    defp apply_error_status(ctx, status_code, error) do
      :telemetry.execute([:trogon_dispatcher, :open_telemetry, :warning], %{count: 1}, %{
        message: "Unknown error status encountered, falling back to error status",
        error: error,
        error_status: status_code
      })

      Span.set_status(ctx, OpenTelemetry.status(:error, format_error(error)))
    end

    defp format_error(%{__exception__: true} = exception), do: Exception.message(exception)
    defp format_error(error) when is_binary(error), do: error
    defp format_error(error), do: inspect(error)
  end
end
