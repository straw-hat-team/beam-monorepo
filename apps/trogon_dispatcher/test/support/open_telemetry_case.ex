defmodule Trogon.Dispatcher.OpenTelemetryCase do
  @moduledoc """
  ExUnit case template for tests that assert on the spans `Trogon.Dispatcher.OpenTelemetry` produces.

  Use `async: false`, since this modifies global OpenTelemetry application state.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Trogon.Dispatcher.OpenTelemetryCase

      require Record

      for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
        Record.defrecord(name, spec)
      end

      for {name, spec} <- Record.extract_all(from_lib: "opentelemetry_api/include/opentelemetry.hrl") do
        Record.defrecord(name, spec)
      end
    end
  end

  setup do
    :application.stop(:opentelemetry)
    :application.set_env(:opentelemetry, :tracer, :otel_tracer_default)
    :application.set_env(:opentelemetry, :traces_exporter, :none)

    :application.set_env(:opentelemetry, :processors, [
      {:otel_batch_processor, %{scheduled_delay_ms: 1}}
    ])

    :application.start(:opentelemetry)
    :otel_batch_processor.set_exporter(:otel_exporter_pid, self())

    on_exit(fn -> detach_handlers() end)

    :ok
  end

  @doc """
  Detaches every handler `Trogon.Dispatcher.OpenTelemetry.setup/1` may have attached.
  """
  def detach_handlers do
    for event <- [
          [:trogon_dispatcher, :dispatch, :start],
          [:trogon_dispatcher, :dispatch, :stop],
          [:trogon_dispatcher, :dispatch, :exception]
        ],
        handler <- :telemetry.list_handlers(event) do
      :telemetry.detach(handler.id)
    end
  end
end
