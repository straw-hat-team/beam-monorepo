defmodule Trogon.Telemetry do
  @moduledoc """
  Emits declared events through `:telemetry`.

  `:telemetry` stays the transport. Nothing here replaces handler dispatch, so anyone can keep attaching
  with `:telemetry.attach/4` and read plain maps. What this package adds is that the two maps are structs
  built from a declaration, which makes them checked at compile time on the way out and pattern matchable
  on the way in.

  Emitting is one function for every event rather than a function generated per module, so there is a
  single place where the wire format is decided.
  """

  alias Trogon.Telemetry.Definition

  @doc """
  Emits a declared event.

      Trogon.Telemetry.execute(%MyApp.Telemetry.LogStreamDelivery{
        measurements: %MyApp.Telemetry.LogStreamDelivery.Measurements{count: 1},
        attributes: %MyApp.Telemetry.LogStreamDelivery.Attributes{result: :ok}
      })

  The envelope itself never reaches the wire. It is taken apart into the measurements and the attributes,
  which travel exactly as built.
  """
  @spec execute(struct()) :: :ok
  def execute(%module{} = event) do
    case module.__telemetry__() do
      %Definition{kind: :event, name: name} ->
        :telemetry.execute(name, event.measurements, event.attributes)

      %Definition{kind: :span} ->
        raise ArgumentError, "#{inspect(module)} is a span, use Trogon.Telemetry.span/2"

      %Definition{kind: :observation} ->
        raise ArgumentError, "#{inspect(module)} observes an event emitted elsewhere, nothing here emits it"
    end
  end

  @doc """
  Runs a function as a span, emitting the start, stop and exception events around it.

  The function returns the result together with the event as it stands at stop time, so the attributes set
  before the call are carried into the stop event instead of being dropped.

      event = %MyApp.Telemetry.DeliverLogStream{
        attributes: %MyApp.Telemetry.DeliverLogStream.Attributes{project_id: project_id}
      }

      Trogon.Telemetry.span(event, fn ->
        case deliver(stream) do
          {:ok, result} -> {{:ok, result}, put_in(event.attributes.result, :ok)}
          {:error, error} -> {{:error, error}, put_in(event.attributes.result, :error)}
        end
      end)

  One declaration is authored, three structs travel. Each phase is projected onto its own pair of
  measurements and attributes, so `MyApp.Telemetry.DeliverLogStream.Start` never carries a field only the
  stop event knows. The projection is a struct literal built at compile time, so nothing walks the
  declaration at run time.

  When the function raises, exits or throws, the exception event is emitted with the attributes as they
  were on start plus `kind`, `reason` and `stacktrace`, and the original error is re-raised untouched.
  """
  @spec span(struct(), (-> {result, struct()})) :: result when result: var
  def span(%module{} = event, fun) when is_function(fun, 0) do
    ensure_span!(module)

    telemetry_span_context = event.attributes.telemetry_span_context || make_ref()
    start_monotonic = System.monotonic_time()

    module.__emit_start__(event, telemetry_span_context, start_monotonic, System.system_time())

    try do
      fun.()
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        stop_monotonic = System.monotonic_time()

        module.__emit_exception__(
          event,
          telemetry_span_context,
          stop_monotonic,
          stop_monotonic - start_monotonic,
          kind,
          reason,
          stacktrace
        )

        :erlang.raise(kind, reason, stacktrace)
    else
      {result, stop_event} when is_struct(stop_event, module) ->
        stop_monotonic = System.monotonic_time()

        module.__emit_stop__(
          stop_event,
          telemetry_span_context,
          stop_monotonic,
          stop_monotonic - start_monotonic
        )

        result

      other ->
        raise ArgumentError,
              "expected the span function to return {result, %#{inspect(module)}{}}, got: #{inspect(other)}"
    end
  end

  defp ensure_span!(module) do
    case module.__telemetry__() do
      %Definition{kind: :span} ->
        :ok

      %Definition{kind: :event} ->
        raise ArgumentError, "#{inspect(module)} is an event, use Trogon.Telemetry.execute/1"

      %Definition{kind: :observation} ->
        raise ArgumentError, "#{inspect(module)} observes an event emitted elsewhere, nothing here emits it"
    end
  end
end
