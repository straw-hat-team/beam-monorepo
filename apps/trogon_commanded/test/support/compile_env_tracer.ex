defmodule Trogon.Commanded.TestSupport.CompileEnvTracer do
  @moduledoc false

  def trace({:compile_env, _app, _path, _return} = event, _env) do
    send(__MODULE__, event)
    :ok
  end

  def trace(_event, _env), do: :ok
end
