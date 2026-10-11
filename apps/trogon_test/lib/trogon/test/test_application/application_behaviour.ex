defmodule Trogon.Test.TestApplication.ApplicationBehaviour do
  @moduledoc false

  @callback get_env(Application.app(), Application.key(), Application.value()) :: Application.value()
  @callback fetch_env(Application.app(), Application.key()) :: {:ok, Application.value()} | :error
  @callback fetch_env!(Application.app(), Application.key()) :: Application.value()
  @callback get_all_env(Application.app()) :: [{Application.key(), Application.value()}]
end
