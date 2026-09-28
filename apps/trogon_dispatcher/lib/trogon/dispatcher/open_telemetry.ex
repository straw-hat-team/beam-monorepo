if Code.ensure_loaded?(OpentelemetryTelemetry) do
  defmodule Trogon.Dispatcher.OpenTelemetry do
    @moduledoc """
    Optional OpenTelemetry integration for `Trogon.Dispatcher`.

    This module only exists when `:opentelemetry_api` and `:opentelemetry_telemetry` are dependencies of the host
    app; nothing in this library requires them.

    ## Usage

    Call `setup/1` once, in your application's `start/2`:

        defmodule MyApp.Application do
          use Application

          def start(_type, _args) do
            Trogon.Dispatcher.OpenTelemetry.setup()

            Supervisor.start_link([MyApp.Dispatcher], strategy: :one_for_one)
          end
        end

    ## Trace context propagation

    Dispatch is synchronous and runs in the caller's process, so the OpenTelemetry context already flows from
    caller to handler without any middleware: the dispatch span is naturally a child of whatever span the caller has
    open. There is nothing to propagate.
    """

    alias OpenTelemetry.Span

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

    @doc """
    Attaches telemetry handlers that turn dispatch spans into OpenTelemetry spans.

    Call once, typically from `Application.start/2`. Calling it twice raises `MatchError`, since the handler id is
    already attached.

    ## Options

      * `:error_status` - a `t:error_status_callback/0` to override the span status set for a returned `:error`.
        Defaults to always setting an error status. Return `nil` from the callback to leave the status unset.

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
      config = Keyword.validate!(opts, error_status: nil)

      :ok = :telemetry.attach_many({__MODULE__, :dispatch}, @events, &__MODULE__.handle_telemetry_event/4, config)
    end

    @doc false
    def handle_telemetry_event(event, measurements, metadata, config)

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :start], _measurements, metadata, _config) do
      destination_name = inspect(metadata.message)
      context = metadata.context

      attributes =
        [
          {:"messaging.system", "trogon_dispatcher"},
          {:"messaging.operation.name", "dispatch"},
          {:"messaging.operation.type", "process"},
          {:"messaging.destination.name", destination_name},
          {:"trogon_dispatcher.message", destination_name},
          {:"trogon_dispatcher.kind", Atom.to_string(metadata.kind)},
          {:"trogon_dispatcher.dispatcher", inspect(metadata.dispatcher)},
          {:"trogon_dispatcher.registered_by", inspect(metadata.registered_by)}
        ]
        |> maybe_add_attribute(:"messaging.message.conversation_id", id_attribute(context.correlation_id))
        |> maybe_add_attribute(:"trogon_dispatcher.correlation_id", id_attribute(context.correlation_id))
        |> maybe_add_attribute(:"trogon_dispatcher.causation_id", id_attribute(context.causation_id))

      OpentelemetryTelemetry.start_telemetry_span(
        @tracer_id,
        "dispatch #{destination_name}",
        metadata,
        %{kind: :internal, attributes: attributes}
      )
    end

    def handle_telemetry_event([:trogon_dispatcher, :dispatch, :stop], measurements, metadata, config) do
      ctx = OpentelemetryTelemetry.set_current_telemetry_span(@tracer_id, metadata)

      if error = metadata[:error] do
        Span.set_attribute(ctx, :"error.type", error_type(error))
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

      Span.set_attribute(ctx, :"erlang.exception.kind", kind)

      exception = Exception.normalize(kind, reason, stacktrace)
      Span.set_attribute(ctx, :"error.type", error_type(exception))
      Span.record_exception(ctx, exception, stacktrace)
      Span.set_status(ctx, OpenTelemetry.status(:error, Exception.format_banner(kind, reason, stacktrace)))

      OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
    end

    defp maybe_add_attribute(attributes, _key, nil), do: attributes
    defp maybe_add_attribute(attributes, key, value), do: [{key, value} | attributes]

    defp id_attribute(nil), do: nil
    defp id_attribute(id) when is_binary(id) or is_integer(id), do: to_string(id)
    defp id_attribute(id) when is_atom(id), do: to_string(id)
    defp id_attribute(_id), do: nil

    defp error_type(error) when is_struct(error), do: inspect(error.__struct__)
    defp error_type(error) when is_atom(error), do: inspect(error)

    defp error_type(error) do
      :telemetry.execute([:trogon_dispatcher, :open_telemetry, :warning], %{count: 1}, %{
        message: "Unknown error type encountered, returning UNKNOWN",
        error: error
      })

      "UNKNOWN"
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
