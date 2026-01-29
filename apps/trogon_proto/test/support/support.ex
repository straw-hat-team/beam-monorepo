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
  Expects System.get_env/1 to be called with the specified env var and return value.

  ## Options

    - `times`: Number of times the call is expected (default: 1)

  ## Example

      expect_system_get_env("DATABASE_URL", "postgres://localhost")
      expect_system_get_env("PORT", "5432", times: 2)
  """
  @spec expect_system_get_env(String.t(), String.t() | nil, keyword()) :: :ok
  def expect_system_get_env(env_var, value, opts \\ []) do
    times = Keyword.get(opts, :times, 1)

    Mox.expect(Trogon.Proto.SystemAdapter.Mock, :get_env, times, fn var ->
      if var == env_var, do: value, else: nil
    end)
  end

  @doc """
  Expects System.get_env/2 to be called with the specified env var, default, and return value.

  ## Options

    - `times`: Number of times the call is expected (default: 1)

  ## Example

      expect_system_get_env_with_default("PORT", "5432", "8080")
      expect_system_get_env_with_default("HOST", "localhost", "0.0.0.0", times: 2)
  """
  @spec expect_system_get_env_with_default(String.t(), String.t(), String.t(), keyword()) :: :ok
  def expect_system_get_env_with_default(env_var, value, default, opts \\ []) do
    times = Keyword.get(opts, :times, 1)

    Mox.expect(Trogon.Proto.SystemAdapter.Mock, :get_env, times, fn var, def ->
      if var == env_var, do: value, else: def
    end)
  end

  @doc """
  Asserts that System.get_env/1 was called with the specified env var.

  Uses Mox.assert_called/1 under the hood to verify the mock received the expected call.

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

  @doc """
  Stubs System.get_env calls with a handler function.

  Useful for testing multiple env vars with different values.

  ## Example

      stub_system_get_env(fn
        "DATABASE_URL" -> "postgres://localhost"
        "PORT" -> "5432"
        _ -> nil
      end)

      stub_system_get_env_with_default(fn
        {"DATABASE_URL", _default} -> "postgres://localhost"
        {"PORT", default} -> default
        {_var, default} -> default
      end)
  """
  @spec stub_system_get_env((String.t() -> String.t() | nil)) :: :ok
  def stub_system_get_env(handler_fn) do
    Mox.stub(Trogon.Proto.SystemAdapter.Mock, :get_env, handler_fn)
  end

  @spec stub_system_get_env_with_default(({String.t(), String.t()} -> String.t() | nil)) :: :ok
  def stub_system_get_env_with_default(handler_fn) do
    Mox.stub(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var, default ->
      handler_fn.({var, default})
    end)
  end
end
