defmodule Trogon.Proto.TestSupport do
  @moduledoc false

  @doc """
  Stubs system environment adapter to return values from the provided map.

  Stubs both SystemAdapter functions: get_env/1 and get_env/2.

  ## Example

      Trogon.Proto.TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret"
      })
  """
  @spec stub_system_env(map()) :: :ok
  def stub_system_env(vars) when is_map(vars) do
    Mox.stub(Trogon.Proto.TestSupport.SystemAdapter.Mock, :get_env, &Map.get(vars, &1))
    Mox.stub(Trogon.Proto.TestSupport.SystemAdapter.Mock, :get_env, &Map.get(vars, &1, &2))
  end
end
