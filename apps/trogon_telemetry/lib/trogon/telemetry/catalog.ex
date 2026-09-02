defmodule Trogon.Telemetry.Catalog do
  @moduledoc """
  The root module an application declares its events under.

  It owns the event name prefix so no event module repeats it, and it is where everything derived from the
  declarations is read: the list of events, the metrics to hand a reporter, the generated documentation.

      defmodule MyApp.Telemetry do
        use Trogon.Telemetry.Catalog,
          otp_app: :my_app,
          prefix: [:my_app]
      end

      defmodule MyApp.Telemetry.LogStreamDelivery do
        use MyApp.Telemetry, :event

        event [:hooks, :log_stream_delivery] do
          # ...
        end
      end

  The catalog resolves its events at runtime, from the modules of its application. Collecting them at
  compile time would mean the catalog depends on every event while every event depends on the catalog.
  """

  alias Trogon.Telemetry.Definition

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @trogon_telemetry_catalog Trogon.Telemetry.Catalog.__options__(opts)

      defmacro __using__(kind) do
        Trogon.Telemetry.Catalog.__define__(__MODULE__, kind)
      end

      @doc false
      @spec __trogon_telemetry_catalog__() :: %{otp_app: atom(), prefix: [atom(), ...]}
      def __trogon_telemetry_catalog__, do: @trogon_telemetry_catalog

      @doc """
      The event name prefix every event in this catalog is declared under.
      """
      @spec prefix() :: [atom(), ...]
      def prefix, do: @trogon_telemetry_catalog.prefix

      @doc """
      The application the events of this catalog are collected from.
      """
      @spec otp_app() :: atom()
      def otp_app, do: @trogon_telemetry_catalog.otp_app

      @doc """
      Every event, span and observation declared under this catalog, sorted by name.
      """
      @spec definitions() :: [Trogon.Telemetry.Definition.t()]
      def definitions, do: Trogon.Telemetry.Catalog.definitions(__MODULE__)

      @doc """
      Every metric declared under this catalog, ready to hand to a reporter.
      """
      @spec metrics() :: [struct()]
      def metrics, do: Trogon.Telemetry.Metrics.for_catalog(__MODULE__)
    end
  end

  @doc false
  @spec __options__(keyword()) :: %{otp_app: atom(), prefix: [atom(), ...]}
  def __options__(opts) do
    opts = Keyword.validate!(opts, [:otp_app, :prefix])
    otp_app = Keyword.fetch!(opts, :otp_app)
    prefix = Keyword.fetch!(opts, :prefix)

    unless is_atom(otp_app) do
      raise ArgumentError, ":otp_app must be an atom, got: #{inspect(otp_app)}"
    end

    unless is_list(prefix) and prefix != [] and Enum.all?(prefix, &is_atom/1) do
      raise ArgumentError, ":prefix must be a non-empty list of atoms, got: #{inspect(prefix)}"
    end

    %{otp_app: otp_app, prefix: prefix}
  end

  @doc false
  @spec __define__(module(), :event | :span) :: Macro.t()
  def __define__(catalog, :event) do
    quote do
      use Trogon.Telemetry.Event, catalog: unquote(catalog)
    end
  end

  def __define__(catalog, :span) do
    quote do
      use Trogon.Telemetry.Span, catalog: unquote(catalog)
    end
  end

  def __define__(catalog, :observation) do
    quote do
      use Trogon.Telemetry.Observation, catalog: unquote(catalog)
    end
  end

  def __define__(catalog, kind) do
    raise ArgumentError,
          "#{inspect(catalog)} can only be used as :event, :span or :observation, got: #{inspect(kind)}"
  end

  @doc """
  Every event, span and observation declared under a catalog, sorted by name.

  Membership is the catalog a module was declared with, not the event name, because an observation describes
  a foreign event that the prefix deliberately does not cover.
  """
  @spec definitions(module()) :: [Definition.t()]
  def definitions(catalog) do
    %{otp_app: otp_app} = catalog.__trogon_telemetry_catalog__()

    otp_app
    |> modules()
    |> Enum.filter(&declaration?/1)
    |> Enum.map(& &1.__telemetry__())
    |> Enum.filter(&(&1.catalog == catalog))
    |> Enum.sort_by(& &1.name)
  end

  defp modules(otp_app) do
    _ = Application.load(otp_app)

    case :application.get_key(otp_app, :modules) do
      {:ok, modules} -> modules
      :undefined -> raise ArgumentError, "the application #{inspect(otp_app)} is not loaded"
    end
  end

  defp declaration?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__telemetry__, 0)
  end
end
