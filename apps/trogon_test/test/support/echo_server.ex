defmodule Trogon.Test.Support.EchoServer do
  @moduledoc false

  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, nil)
  end

  def get_env(server, app, key, default \\ nil) do
    GenServer.call(server, {:get_env, app, key, default})
  end

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call({:get_env, app, key, default}, _from, state) do
    {:reply, Trogon.Test.Application.get_env(app, key, default), state}
  end
end
