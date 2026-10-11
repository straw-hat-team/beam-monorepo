defmodule Trogon.Commanded.Features do
  @moduledoc false

  @app :trogon_commanded

  @spec enabled?(env :: Macro.Env.t(), feature :: atom(), overrides :: keyword()) :: boolean()
  def enabled?(%Macro.Env{} = env, feature, overrides) when is_atom(feature) and is_list(overrides) do
    case Keyword.fetch(overrides, feature) do
      {:ok, value} -> value == true
      :error -> Application.compile_env(env, @app, [:features, feature], false) == true
    end
  end
end
