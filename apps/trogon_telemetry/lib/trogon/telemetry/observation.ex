defmodule Trogon.Telemetry.Observation do
  @moduledoc """
  Declares an event emitted by somebody else.

  Ecto, Oban, Cowboy and the rest emit their own `:telemetry` events, so nothing here can own them. What can
  still be declared is what those events carry and which metrics they should feed, which is enough to derive
  the same `Telemetry.Metrics` definitions and the same documentation as an event of your own.

      defmodule MyApp.Telemetry.EctoQuery do
        use MyApp.Telemetry, :observation

        @moduledoc "Every query the repo runs."

        observe [:my_app, :repo, :query] do
          measurements do
            field :total_time, :integer,
              metric: :histogram,
              unit: {:native, :millisecond},
              doc: "Queue, query and decode time together."

            field :query_time, :integer, metric: :histogram, unit: {:native, :millisecond}
          end

          attributes do
            field :source, :string, tag: true
          end
        end
      end

  The name is used exactly as written. A catalog prefix is not applied, because the prefix says which events
  are yours and these are not.

  Nothing is emitted for an observation and no struct is generated, so `Trogon.Telemetry.execute/1` refuses
  one. The measurements and attributes it declares describe the plain maps the other library already sends.
  """

  @doc """
  Declares the foreign event name and its two sections.
  """
  @spec observe(term(), Macro.t()) :: Macro.t()
  defmacro observe(name, do: block) do
    quote do
      Trogon.Telemetry.Schema.__name__(__MODULE__, unquote(name))
      unquote(block)
    end
  end

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import Trogon.Telemetry.Observation, only: [observe: 2]
      import Trogon.Telemetry.Schema, only: [measurements: 1, attributes: 1, field: 2, field: 3]

      Trogon.Telemetry.Schema.__setup__(__MODULE__, :observation, opts[:catalog])

      @before_compile Trogon.Telemetry.Schema
    end
  end
end
