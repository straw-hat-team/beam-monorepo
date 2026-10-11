defmodule Trogon.Test.TestApplication.ElixirApplication do
  @moduledoc false
  @behaviour Trogon.Test.TestApplication.ApplicationBehaviour

  @impl true
  defdelegate get_env(app, key, default), to: Application

  @impl true
  defdelegate fetch_env(app, key), to: Application

  @impl true
  defdelegate fetch_env!(app, key), to: Application

  @impl true
  defdelegate get_all_env(app), to: Application
end
