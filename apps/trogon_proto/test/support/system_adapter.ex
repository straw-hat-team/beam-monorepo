defmodule Trogon.Proto.TestSupport.SystemAdapter do
  @moduledoc """
  Behavior for system environment operations.

  In production, uses System module directly via Application.compile_env.
  In tests, can be mocked via Mox for testing environment variable handling.
  """

  @callback get_env(String.t()) :: String.t() | nil
  @callback get_env(String.t(), String.t()) :: String.t()
  @callback fetch_env!(String.t()) :: String.t()
end
