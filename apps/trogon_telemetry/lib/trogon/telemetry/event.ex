defmodule Trogon.Telemetry.Event do
  @moduledoc """
  Declares a single `:telemetry` event as a struct.

  The module becomes the envelope holding the two maps `:telemetry` carries, and each of them gets its own
  generated struct. Emitting goes through `Trogon.Telemetry.execute/1`, never through a function on the
  event module itself.

      defmodule MyApp.Telemetry.LogStreamDelivery do
        use MyApp.Telemetry, :event

        @moduledoc "Emitted once per delivery attempt to a log stream destination."

        event [:hooks, :log_stream_delivery] do
          measurements do
            field :count, :integer, default: 1
          end

          attributes do
            field :project_id, MyApp.ProjectId, tag: true
            field :destination, MyApp.LogStream.Destination, tag: true
            field :result, {:enum, [:ok, :error]}, tag: true
          end
        end
      end

      Trogon.Telemetry.execute(%MyApp.Telemetry.LogStreamDelivery{
        attributes: %MyApp.Telemetry.LogStreamDelivery.Attributes{
          project_id: project_id,
          destination: destination,
          result: result
        }
      })

  Declared defaults mean the measurements can be left out entirely when they carry nothing dynamic.

  Using this module directly instead of through a `Trogon.Telemetry.Catalog` is supported, and then the
  event name is taken as written rather than being prefixed.
  """

  @doc """
  Declares the event name and its two sections.

  With a catalog the name is relative to the catalog prefix. Without one it is used as written.
  """
  @spec event(term(), Macro.t()) :: Macro.t()
  defmacro event(name, do: block) do
    quote do
      Trogon.Telemetry.Schema.__name__(__MODULE__, unquote(name))
      unquote(block)
    end
  end

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import Trogon.Telemetry.Event, only: [event: 2]
      import Trogon.Telemetry.Schema, only: [measurements: 1, attributes: 1, field: 2, field: 3]

      Trogon.Telemetry.Schema.__setup__(__MODULE__, :event, opts[:catalog])

      @before_compile Trogon.Telemetry.Schema
    end
  end
end
