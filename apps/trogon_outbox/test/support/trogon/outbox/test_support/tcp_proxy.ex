defmodule Trogon.Outbox.TestSupport.TcpProxy do
  @moduledoc false

  use GenServer

  @poll_interval_ms 10
  @paused 1
  @lose_commit_reply 2
  @severed 3

  @doc """
  Forwards connections on a local port to `host:port`. While paused, every
  connection stays open but no byte moves in either direction, which is what a
  database behind a stalled network or a failing over primary looks like to a
  client. While severed, every live connection is closed and every new one is
  refused, which is what the service itself being down looks like to a client.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec port(pid()) :: :inet.port_number()
  def port(proxy), do: GenServer.call(proxy, :port)

  @spec pause(pid()) :: :ok
  def pause(proxy), do: GenServer.call(proxy, {:paused, true})

  @spec resume(pid()) :: :ok
  def resume(proxy), do: GenServer.call(proxy, {:paused, false})

  @doc """
  Closes every live connection and refuses every new one, until `restore/1` is called. The
  listener keeps running on the same port; a connection attempt while severed is accepted and
  closed immediately, the same as a client reaching a port nothing answers behind.
  """
  @spec sever(pid()) :: :ok
  def sever(proxy), do: GenServer.call(proxy, :sever)

  @doc "Accepts and forwards connections again, on the same port `sever/1` closed."
  @spec restore(pid()) :: :ok
  def restore(proxy), do: GenServer.call(proxy, :restore)

  @doc """
  Arms the proxy so the next connection that sends a `COMMIT` has it delivered,
  but never sees the reply: the proxy drops the reply and closes that
  connection, so the transaction commits while the client only sees a broken
  connection.
  """
  @spec lose_next_commit_reply(pid()) :: :ok
  def lose_next_commit_reply(proxy), do: GenServer.call(proxy, :lose_next_commit_reply)

  @impl GenServer
  def init(opts) do
    host = opts |> Keyword.fetch!(:host) |> String.to_charlist()
    upstream_port = Keyword.fetch!(opts, :port)
    flags = :atomics.new(3, [])

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)

    proxy = self()
    acceptor = spawn_link(fn -> accept(proxy, listener, host, upstream_port, flags) end)

    {:ok, %{listener: listener, port: port, flags: flags, acceptor: acceptor, sockets: MapSet.new()}}
  end

  @impl GenServer
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call({:paused, paused?}, _from, state) do
    :atomics.put(state.flags, @paused, if(paused?, do: 1, else: 0))
    {:reply, :ok, state}
  end

  def handle_call(:sever, _from, state) do
    :atomics.put(state.flags, @severed, 1)
    Enum.each(state.sockets, &:gen_tcp.close/1)
    {:reply, :ok, %{state | sockets: MapSet.new()}}
  end

  def handle_call(:restore, _from, state) do
    :atomics.put(state.flags, @severed, 0)
    {:reply, :ok, state}
  end

  def handle_call(:lose_next_commit_reply, _from, state) do
    :atomics.put(state.flags, @lose_commit_reply, 1)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:register, client, upstream}, state) do
    {:noreply, %{state | sockets: state.sockets |> MapSet.put(client) |> MapSet.put(upstream)}}
  end

  defp accept(proxy, listener, host, upstream_port, flags) do
    case :gen_tcp.accept(listener) do
      {:ok, client} ->
        if :atomics.get(flags, @severed) == 1 do
          :gen_tcp.close(client)
        else
          {:ok, upstream} = :gen_tcp.connect(host, upstream_port, [:binary, active: false])
          GenServer.cast(proxy, {:register, client, upstream})
          losing_reply = :atomics.new(1, [])

          spawn(fn ->
            pump(%{from: client, to: upstream, flags: flags, losing_reply: losing_reply, direction: :request})
          end)

          spawn(fn ->
            pump(%{from: upstream, to: client, flags: flags, losing_reply: losing_reply, direction: :reply})
          end)
        end

        accept(proxy, listener, host, upstream_port, flags)

      {:error, :closed} ->
        :ok
    end
  end

  defp pump(%{from: from, to: to, flags: flags} = pipe) do
    if :atomics.get(flags, @paused) == 1 do
      Process.sleep(@poll_interval_ms)
      pump(pipe)
    else
      case :gen_tcp.recv(from, 0, @poll_interval_ms) do
        {:ok, data} -> forward(pipe, data)
        {:error, :timeout} -> pump(pipe)
        {:error, _closed} -> :gen_tcp.close(to)
      end
    end
  end

  defp forward(%{direction: :reply, losing_reply: losing_reply} = pipe, data) do
    if :atomics.get(losing_reply, 1) == 1 do
      :gen_tcp.close(pipe.from)
      :gen_tcp.close(pipe.to)
    else
      send_on(pipe, data)
    end
  end

  defp forward(%{direction: :request} = pipe, data) do
    if :binary.match(data, "COMMIT") != :nomatch and
         :atomics.compare_exchange(pipe.flags, @lose_commit_reply, 1, 0) == :ok do
      :atomics.put(pipe.losing_reply, 1, 1)
    end

    send_on(pipe, data)
  end

  defp send_on(pipe, data) do
    case :gen_tcp.send(pipe.to, data) do
      :ok -> pump(pipe)
      {:error, _closed} -> :gen_tcp.close(pipe.from)
    end
  end
end
