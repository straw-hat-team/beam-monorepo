defmodule Trogon.Proto.SystemAdapter do
  @moduledoc """
  Behavior for system environment operations.

  Allows mocking System functions in tests.
  """

  @callback get_env(String.t()) :: String.t() | nil
  @callback get_env(String.t(), String.t()) :: String.t()
  @callback put_env(String.t(), String.t()) :: :ok
  @callback delete_env(String.t()) :: :ok
end

defmodule Trogon.Proto.SystemAdapter.Default do
  @moduledoc """
  Default implementation using the actual System module.
  """

  @behaviour Trogon.Proto.SystemAdapter

  @impl true
  def get_env(name) do
    System.get_env(name)
  end

  @impl true
  def get_env(name, default) do
    System.get_env(name, default)
  end

  @impl true
  def put_env(name, value) do
    System.put_env(name, value)
  end

  @impl true
  def delete_env(name) do
    System.delete_env(name)
  end
end
