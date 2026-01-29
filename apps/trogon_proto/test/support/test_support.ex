defmodule Trogon.Proto.TestSupport do
  @moduledoc """
  Test support utilities for Trogon.Proto tests.
  """

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
  Configures Mox to use a specific system adapter mock configuration.

  ## Example

      setup do
        Trogon.Proto.TestSupport.setup_mox(:system_adapter)
        :ok
      end
  """
  @spec setup_mox(atom()) :: :ok
  def setup_mox(:system_adapter) do
    # Verify that all expectations on the mock are met
    Mox.verify_on_exit!(Trogon.Proto.SystemAdapter.Mock)
    :ok
  end

  @doc """
  Expects a System.get_env/1 call on the mock.

  ## Example

      expect_get_env("DATABASE_URL", "postgres://localhost")
  """
  @spec expect_get_env(String.t(), String.t() | nil) :: :ok
  def expect_get_env(env_var, value) do
    Mox.expect(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var ->
      if var == env_var, do: value, else: nil
    end)
  end

  @doc """
  Stubs a System.get_env/2 call on the mock with default value support.

  ## Example

      stub_get_env_with_default("PORT", fn
        "PORT" -> "5432"
        _ -> nil
      end)
  """
  @spec stub_get_env_with_default(String.t(), (String.t() -> String.t() | nil)) :: :ok
  def stub_get_env_with_default(env_var, handler_fn) do
    Mox.stub(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var ->
      handler_fn.(var)
    end)

    Mox.stub(Trogon.Proto.SystemAdapter.Mock, :get_env, fn var, default ->
      handler_fn.(var) || default
    end)
  end
end
