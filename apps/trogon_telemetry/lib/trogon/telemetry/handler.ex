defmodule Trogon.Telemetry.Handler do
  @moduledoc """
  Receives declared events as the struct they were emitted as.

  `:telemetry` hands a handler two loose maps and the event name. A handler built here gets the envelope
  back instead, rebuilt from those maps, so the same struct is pattern matched on both sides of the wire.

      defmodule MyApp.Telemetry.DeliveryLogger do
        use Trogon.Telemetry.Handler, events: [MyApp.Telemetry.LogStreamDelivery]

        alias MyApp.Telemetry.LogStreamDelivery

        @impl true
        def handle(%LogStreamDelivery{attributes: %{result: :error} = attributes}, :event, _config) do
          Logger.warning("delivery failed for \#{inspect(attributes.project_id)}")
        end

        def handle(_event, _phase, _config), do: :ok
      end

      MyApp.Telemetry.DeliveryLogger.attach()

  A span reaches `c:handle/3` once per phase, and every phase has its own envelope, so a clause names the
  phase it cares about by the struct it matches.

      def handle(%DeliverLogStream.Stop{measurements: measurements}, :stop, _config) do
        Logger.info("delivered in \#{measurements.duration}")
      end

  The second argument says the same thing as the struct name, which is what makes a catch-all clause
  possible.

  Aliasing the phase is the shortest way to write that, and it is the only name worth aliasing. With
  `alias MyApp.Telemetry.DeliverLogStream.Stop` in scope, both `%Stop{}` and `%Stop.Attributes{}` are
  reachable. Aliasing a section directly is what collides, since every event owns a `Measurements` and an
  `Attributes`, and a second alias of the same leaf silently wins.

  Aliasing the exception phase shadows `Exception` for that module. The shadow announces itself rather
  than hiding, since the generated module is a bare struct, so any later call such as `Exception.message/1`
  warns that the function is undefined.
  """

  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.Definition.Field

  @doc """
  Handles one emitted event.

  The phase is `:event` for a plain event, and `:start`, `:stop` or `:exception` for a span.
  """
  @callback handle(event :: struct(), phase :: Field.phase(), config :: term()) :: term()

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Trogon.Telemetry.Handler

      @trogon_telemetry_handler_events Keyword.fetch!(opts, :events)

      @doc false
      @spec __telemetry_events__() :: [module()]
      def __telemetry_events__, do: @trogon_telemetry_handler_events

      @doc """
      Attaches this handler to every event it declares.

      Attaching twice is a no-op, so it is safe to call from a supervision tree that restarts.
      """
      @spec attach(term()) :: :ok
      def attach(config \\ nil), do: Trogon.Telemetry.Handler.attach(__MODULE__, config)

      @doc """
      Detaches this handler.
      """
      @spec detach() :: :ok | {:error, :not_found}
      def detach, do: Trogon.Telemetry.Handler.detach(__MODULE__)
    end
  end

  @doc """
  Attaches a handler module to every event it declares.
  """
  @spec attach(module(), term()) :: :ok
  def attach(handler, config) do
    routes = routes(handler)

    case :telemetry.attach_many(handler, Map.keys(routes), &Trogon.Telemetry.Handler.__dispatch__/4, %{
           handler: handler,
           routes: routes,
           config: config
         }) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc """
  Detaches a handler module.
  """
  @spec detach(module()) :: :ok | {:error, :not_found}
  def detach(handler), do: :telemetry.detach(handler)

  @doc false
  @spec __dispatch__([atom(), ...], map(), map(), map()) :: term()
  def __dispatch__(name, measurements, attributes, %{handler: handler, routes: routes, config: config}) do
    {module, phase} = Map.fetch!(routes, name)

    handler.handle(struct(module, measurements: measurements, attributes: attributes), phase, config)
  end

  defp routes(handler) do
    for module <- handler.__telemetry_events__(),
        definition = owned!(module),
        {phase, name} <- Definition.emitted(definition),
        into: %{},
        do: {name, {Definition.wire_module(definition, phase), phase}}
  end

  defp owned!(module) do
    definition = module.__telemetry__()

    unless Definition.owned?(definition) do
      raise ArgumentError,
            "#{inspect(module)} observes an event emitted elsewhere, so there is no struct to rebuild. " <>
              "Attach to it with :telemetry.attach/4"
    end

    definition
  end
end
