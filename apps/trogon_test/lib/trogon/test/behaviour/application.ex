defmodule Trogon.Test.Behaviour.Application do
  @moduledoc """
  The `Application` environment functions `Trogon.Test.MockApplication` mocks.
  """

  @callback get_env(Application.app(), Application.key(), Application.value()) :: Application.value()
  @callback fetch_env(Application.app(), Application.key()) :: {:ok, Application.value()} | :error
  @callback fetch_env!(Application.app(), Application.key()) :: Application.value()
  @callback get_all_env(Application.app()) :: [{Application.key(), Application.value()}]
end
