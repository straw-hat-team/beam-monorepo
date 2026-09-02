defmodule Trogon.Telemetry.Span do
  @moduledoc """
  Declares a span as a struct.

  A span is three events sharing one declaration, so the name given here is a prefix and `:start`,
  `:stop` and `:exception` are appended to it. The measurements and attributes `:telemetry` conventions
  require are declared for you and documented alongside your own fields.

      defmodule MyApp.Telemetry.DeliverLogStream do
        use MyApp.Telemetry, :span

        @moduledoc "Wraps a single delivery attempt."

        span [:hooks, :deliver_log_stream] do
          measurements do
            field :bytes_sent, :integer
          end

          attributes do
            field :project_id, MyApp.ProjectId, tag: true
            field :result, {:enum, [:ok, :error]}, tag: true, phase: :stop
          end
        end
      end

  See `Trogon.Telemetry.span/2` for how one is run.
  """

  @doc """
  Declares the span name prefix and its two sections.

  ## Options

  - `:duration` - the metric the reserved `duration` measurement feeds. Defaults to a histogram in
    milliseconds, since how long something took is the reason most spans exist. Takes the same options as a
    measurement, or `false` to derive nothing.

        span [:hooks, :deliver_log_stream], duration: [unit: {:native, :microsecond}] do
  """
  @spec span(term(), keyword(), Macro.t()) :: Macro.t()
  defmacro span(name, opts \\ [], do: block) do
    quote do
      Trogon.Telemetry.Schema.__name__(__MODULE__, unquote(name))
      Trogon.Telemetry.Schema.__span__(__MODULE__, unquote(opts))
      unquote(block)
    end
  end

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import Trogon.Telemetry.Span, only: [span: 2, span: 3]
      import Trogon.Telemetry.Schema, only: [measurements: 1, attributes: 1, field: 2, field: 3]

      Trogon.Telemetry.Schema.__setup__(__MODULE__, :span, opts[:catalog])

      @before_compile Trogon.Telemetry.Schema
    end
  end
end
