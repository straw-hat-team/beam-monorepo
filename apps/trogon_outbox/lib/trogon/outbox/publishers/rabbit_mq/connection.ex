defmodule Trogon.Outbox.Publishers.RabbitMQ.Connection do
  @moduledoc """
  Keeps one `AMQP.Connection` open to a broker, reconnecting on loss.

  `Trogon.Outbox.Publishers.RabbitMQ` asks this process for the current connection on every
  publish instead of holding one itself, so a relay keeps retrying through a broker restart
  without ever publishing on a dead connection, and reconnects without the relay noticing.

  ## Options

    * `:url` - the AMQP connection URI. Required.
    * `:retry_interval` - how long to wait before retrying a failed connection attempt, in
      milliseconds, 1000 by default.
    * `:name` - the process name.
  """

  use GenServer

  @type option :: {:url, String.t()} | {:retry_interval, pos_integer()} | {:name, GenServer.name()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "The current connection, or `{:error, :disconnected}` while there is none."
  @spec get(GenServer.server(), timeout()) :: {:ok, AMQP.Connection.t()} | {:error, :disconnected}
  def get(server, timeout \\ 5_000), do: GenServer.call(server, :get, timeout)

  @impl GenServer
  def init(opts) do
    state = %{
      url: Keyword.fetch!(opts, :url),
      retry_interval: Keyword.get(opts, :retry_interval, 1_000),
      connection: nil
    }

    {:ok, connect(state)}
  end

  @impl GenServer
  def handle_call(:get, _from, %{connection: nil} = state), do: {:reply, {:error, :disconnected}, state}
  def handle_call(:get, _from, %{connection: connection} = state), do: {:reply, {:ok, connection}, state}

  @impl GenServer
  def handle_info(:connect, state), do: {:noreply, connect(state)}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{connection: %{pid: pid}} = state),
    do: {:noreply, schedule_connect(%{state | connection: nil})}

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  defp connect(state) do
    case AMQP.Connection.open(state.url) do
      {:ok, connection} ->
        Process.monitor(connection.pid)
        %{state | connection: connection}

      {:error, _reason} ->
        schedule_connect(state)
    end
  end

  defp schedule_connect(state) do
    Process.send_after(self(), :connect, state.retry_interval)
    state
  end
end
