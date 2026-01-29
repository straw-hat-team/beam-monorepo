defmodule Trogon.Proto.TestSupport do
  @moduledoc """
  Test support utilities for Trogon.Proto tests.

  Includes helpers for:
  - UuidTemplate with proto-generated enums
  - System environment variable mocking and assertion
  - Test setup and cleanup utilities
  """

  alias Acme.Order.V1.OrderId
  alias Acme.Singleton.V1.SingletonId
  alias Acme.Resource.V1.ResourceId
  alias Acme.Entity.V1.EntityId
  alias Acme.ValueNamespace.V1.ValueNamespaceId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  defmodule AcmeOrderId do
    @moduledoc "Dynamic template with DNS namespace and multi-key template."
    use UuidTemplate,
      enum: OrderId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule StaticSingletonId do
    @moduledoc "Static template with no placeholders."
    use UuidTemplate,
      enum: SingletonId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule DnsNamespaceId do
    @moduledoc "DNS namespace example."
    use UuidTemplate,
      enum: OrderId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule UrlNamespaceId do
    @moduledoc "URL namespace example."
    use UuidTemplate,
      enum: ResourceId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule UuidNamespaceId do
    @moduledoc "Custom UUID namespace example."
    use UuidTemplate,
      enum: EntityId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  # Namespace resolution tests

  defmodule ValueNamespaceV1Id do
    @moduledoc "V1 uses enum-level namespace (no value-level override)."
    use UuidTemplate,
      enum: ValueNamespaceId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule ValueNamespaceV2Id do
    @moduledoc "V2 overrides with value-level namespace."
    use UuidTemplate,
      enum: ValueNamespaceId.IdentityVersion,
      version: :IDENTITY_VERSION_V2
  end

  # System Environment Adapter Test Helpers

  @doc """
  Sets environment variables from a map and returns a cleanup function.

  ## Example

      setup do
        cleanup = Trogon.Proto.TestSupport.setup_env(%{
          "DATABASE_URL" => "postgres://localhost",
          "PORT" => "5432"
        })

        on_exit(fn -> cleanup.() end)
        :ok
      end
  """
  @spec setup_env(map()) :: (-> :ok)
  def setup_env(env_vars) when is_map(env_vars) do
    existing_values = Map.new(env_vars, fn {key, _} -> {key, System.get_env(key)} end)

    Enum.each(env_vars, fn {key, value} ->
      System.put_env(key, value)
    end)

    fn ->
      Enum.each(existing_values, fn {key, value} ->
        case value do
          nil -> System.delete_env(key)
          val -> System.put_env(key, val)
        end
      end)

      :ok
    end
  end

  @doc """
  Cleans up environment variables by deleting them.

  ## Example

      on_exit(fn ->
        Trogon.Proto.TestSupport.cleanup_env(["DATABASE_URL", "PORT"])
      end)
  """
  @spec cleanup_env([String.t()]) :: :ok
  def cleanup_env(env_vars) when is_list(env_vars) do
    Enum.each(env_vars, &System.delete_env/1)
  end

  @doc """
  Expects System.get_env/1 to be called with the specified env var.

  ## Options

    - `times`: Number of times the call is expected (default: 1)
    - `returns`: Value to return from the call

  ## Example

      expect_system_get_env("DATABASE_URL", times: 1, returns: "postgres://localhost")
      expect_system_get_env("PORT", times: 2, returns: "5432")
  """
  @spec expect_system_get_env(String.t(), keyword()) :: :ok
  def expect_system_get_env(env_var, opts \\ []) do
    times = Keyword.get(opts, :times, 1)
    returns = Keyword.fetch!(opts, :returns)

    Mox.expect(Trogon.Proto.SystemAdapter.Mock, :get_env, times, fn var ->
      if var == env_var, do: returns, else: nil
    end)
  end

  @doc """
  Expects System.get_env/2 to be called with the specified env var and default.

  ## Options

    - `times`: Number of times the call is expected (default: 1)
    - `returns`: Value to return from the call

  ## Example

      expect_system_get_env_with_default("PORT", "8080", times: 1, returns: "5432")
      expect_system_get_env_with_default("HOST", "0.0.0.0", times: 2, returns: "localhost")
  """
  @spec expect_system_get_env_with_default(String.t(), String.t(), keyword()) :: :ok
  def expect_system_get_env_with_default(env_var, default, opts \\ []) do
    times = Keyword.get(opts, :times, 1)
    returns = Keyword.fetch!(opts, :returns)

    Mox.expect(Trogon.Proto.SystemAdapter.Mock, :get_env, times, fn var, def ->
      if var == env_var, do: returns, else: def
    end)
  end

  @doc """
  Asserts that System.get_env/1 was called with the specified env var.

  ## Example

      assert_received_system_get_env("DATABASE_URL")
  """
  @spec assert_received_system_get_env(String.t()) :: :ok
  def assert_received_system_get_env(env_var) do
    Mox.assert_called(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var ->
      var == env_var
    end)
  end

  @doc """
  Asserts that System.get_env/2 was called with the specified env var and default.

  ## Example

      assert_received_system_get_env_with_default("PORT", "5432")
  """
  @spec assert_received_system_get_env_with_default(String.t(), String.t()) :: :ok
  def assert_received_system_get_env_with_default(env_var, default) do
    Mox.assert_called(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var, def ->
      var == env_var and def == default
    end)
  end
end
