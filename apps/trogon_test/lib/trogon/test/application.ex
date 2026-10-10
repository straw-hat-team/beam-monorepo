defmodule Trogon.Test.Application do
  @moduledoc """
  A per-test, async-safe stand-in for `Application`.

  `Application.put_env/3` writes to the application controller's table, the same
  global, node-wide state every process reads from with `Application.get_env/2,3`.
  A test that calls it changes what every other test concurrently running reads,
  not only its own, so the test cannot run `async: true`, and the `on_exit` that
  restores the previous value races whatever else reads or writes the same key
  while it runs.

  A project reads configuration through a facade it compiles in, `Application` in
  every environment but test:

      defmodule MyApp.Config do
        @application Application.compile_env(:my_app, [MyApp, :application], Application)

        defdelegate get_env(app, key, default \\\\ nil), to: @application
      end

  and in `config/test.exs`:

      config :my_app, MyApp, application: Trogon.Test.Application

  Each test then overrides the config it cares about, scoped to its own process:

      test "charges the configured tax rate" do
        Trogon.Test.Application.put_env(:my_app, :tax_rate, 0.07)
        assert MyApp.Billing.tax_rate() == 0.07
      end

  The override belongs to the calling process, called the *owner*. It is visible
  to the owner itself, to any of the owner's `$callers` (the process that started
  a `Task`, for instance), and to a process named with `allow/2`. It is invisible
  to every other process, and it disappears on its own when the owner exits, so
  no test needs an `on_exit` callback to restore the value it changed.

  Read functions fall through to the real `Application` once there is no
  override for a key: `get_env/2`, `get_env/3`, `fetch_env/2`, `fetch_env!/2`, and
  `get_all_env/1`. Write functions scope the change to the calling process:
  `put_env/3`, `merge_env/3`, and `delete_env/2`.

  > #### Do not alias this module without `as:` {: .warning}
  >
  > `alias Trogon.Test.Application` shadows the real `Application` module for
  > the rest of that file. Give it another name instead:
  >
  >     alias Trogon.Test.Application, as: TestApplication

  ## Examples

      iex> Trogon.Test.Application.get_env(:trogon_test, :does_not_exist, :default)
      :default
      iex> Trogon.Test.Application.put_env(:trogon_test, :does_not_exist, :overridden)
      :ok
      iex> Trogon.Test.Application.get_env(:trogon_test, :does_not_exist, :default)
      :overridden
      iex> Trogon.Test.Application.delete_env(:trogon_test, :does_not_exist)
      :ok
      iex> Trogon.Test.Application.get_env(:trogon_test, :does_not_exist, :default)
      :default

  """

  @ownership_server Trogon.Test.Ownership
  @ownership_key __MODULE__

  @typedoc "An application name, same as `t:Application.app/0`."
  @type app :: atom()

  @typedoc "A configuration key, same as `t:Application.key/0`."
  @type key :: atom()

  @typedoc "A configuration value, same as `t:Application.value/0`."
  @type value :: term()

  @typedoc "A PID, or a zero-arity function that resolves to a PID or a list of PIDs."
  @type allowed :: pid() | (-> pid() | [pid()])

  @doc """
  Returns the value for `key` in `app`'s environment.

  Reads the override owned by `self()` or by any of its `$callers` first, and
  falls through to `Application.get_env/3` when there is none.
  """
  @spec get_env(app(), key(), value()) :: value()
  def get_env(app, key, default \\ nil) do
    case fetch_override(app, key) do
      {:ok, {:value, value}} -> value
      {:ok, :deleted} -> default
      :error -> Application.get_env(app, key, default)
    end
  end

  @doc """
  Returns the value for `key` in `app`'s environment, in a tuple.

  Mirrors `Application.fetch_env/2`: returns `:error` when the configuration
  parameter does not exist, considering an override that deletes it as not
  existing.
  """
  @spec fetch_env(app(), key()) :: {:ok, value()} | :error
  def fetch_env(app, key) do
    case fetch_override(app, key) do
      {:ok, {:value, value}} -> {:ok, value}
      {:ok, :deleted} -> :error
      :error -> Application.fetch_env(app, key)
    end
  end

  @doc """
  Returns the value for `key` in `app`'s environment, raising if missing.

  Raises the same `ArgumentError` that `Application.fetch_env!/2` would raise.
  """
  @spec fetch_env!(app(), key()) :: value()
  def fetch_env!(app, key) do
    case fetch_env(app, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "could not fetch application environment #{inspect(key)} for application " <>
                "#{inspect(app)} #{fetch_env_failed_reason(app, key)}"
    end
  end

  @doc """
  Returns all the key-value pairs for `app`.

  Starts from `Application.get_all_env/1` and applies the override owned by
  `self()` or any of its `$callers` on top, removing the keys an override
  deleted.
  """
  @spec get_all_env(app()) :: [{key(), value()}]
  def get_all_env(app) do
    case fetch_override_app(app) do
      {:ok, overrides} ->
        app
        |> Application.get_all_env()
        |> Map.new()
        |> apply_overrides(overrides)
        |> Enum.to_list()

      :error ->
        Application.get_all_env(app)
    end
  end

  @doc """
  Puts `value` in `key` for `app`, for the calling process alone.

  Same semantics as `Application.put_env/3`: the next read, from the owner or
  from one of its `$callers`, sees `value` in place of whatever `key` held
  before, until the owner changes or deletes it, or the owner exits.

  Called from one of the owner's `$callers`, or from a process named with
  `allow/2`, the write lands in the owner's overrides, so every process that
  reads them sees it. With no owner yet, the outermost of the `$callers`, the
  test process that started the `Task` for instance, becomes the owner. Every
  write function behaves this way.
  """
  @spec put_env(app(), key(), value()) :: :ok
  def put_env(app, key, value) do
    update_override(app, key, fn _current -> {:value, value} end)
  end

  @doc """
  Deep merges `value` onto the current effective value of `key` in `app`,
  for the calling process alone.

  Reads the current effective value the way `get_env/2` would, then merges
  `value` onto it with `Config.Reader.merge/2`, the same function `mix`
  itself uses to merge configuration files: keyword lists merge recursively,
  key by key, and any other value is replaced outright.
  """
  @spec merge_env(app(), key(), value()) :: :ok
  def merge_env(app, key, value) do
    update_override(app, key, fn current ->
      current_value =
        case current do
          {:value, overridden} -> overridden
          :deleted -> nil
          nil -> Application.get_env(app, key)
        end

      left = if is_nil(current_value), do: [], else: [{key, current_value}]
      merged = Config.Reader.merge([{app, left}], [{app, [{key, value}]}])
      {:value, get_in(merged, [app, key])}
    end)
  end

  @doc """
  Deletes `key` from `app`'s environment, for the calling process alone.

  The key reads as missing, through `get_env/2`, `fetch_env/2`, `fetch_env!/2`,
  and `get_all_env/1`, to the owner and to its `$callers`, no matter what the
  real `Application` holds for it. Every other process keeps reading the real
  value.
  """
  @spec delete_env(app(), key()) :: :ok
  def delete_env(app, key) do
    update_override(app, key, fn _current -> :deleted end)
  end

  @doc """
  Lets `pid_or_lazy_fun` read the overrides owned by `owner` (`self()` by
  default).

  Use this for a process `$callers` does not cover, such as a `GenServer`
  started outside of a `Task`. `pid_or_lazy_fun` can be a PID, or a zero-arity
  function returning a PID (or a list of PIDs) once the process exists, for
  when it is not started yet at the point `allow/2` is called. Mirrors
  `NimbleOwnership.allow/4`: allowing a PID already allowed through a
  different owner, or allowing it while `owner` is not itself a valid owner
  of another owner's override, returns an error.
  """
  @spec allow(pid(), allowed()) :: :ok | {:error, NimbleOwnership.Error.t()}
  def allow(owner \\ self(), pid_or_lazy_fun) do
    ensure_owner(owner)
    NimbleOwnership.allow(@ownership_server, owner, pid_or_lazy_fun, @ownership_key)
  end

  defp update_override(app, key, fun) do
    owner =
      case fetch_owner() do
        {:ok, owner} -> owner
        :error -> List.last(callers())
      end

    @ownership_server
    |> NimbleOwnership.get_and_update(owner, @ownership_key, fn overrides ->
      overrides = overrides || %{}
      app_overrides = Map.get(overrides, app, %{})
      current = Map.get(app_overrides, key)
      new_app_overrides = Map.put(app_overrides, key, fun.(current))
      {:ok, Map.put(overrides, app, new_app_overrides)}
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, %NimbleOwnership.Error{} = error} -> raise error
    end
  end

  defp ensure_owner(owner) do
    NimbleOwnership.get_and_update(@ownership_server, owner, @ownership_key, fn overrides ->
      {:ok, overrides || %{}}
    end)

    :ok
  end

  defp fetch_override(app, key) do
    with {:ok, app_overrides} <- fetch_override_app(app),
         {:ok, marker} <- Map.fetch(app_overrides, key) do
      {:ok, marker}
    else
      _ -> :error
    end
  end

  defp fetch_override_app(app) do
    with {:ok, owner} <- fetch_owner(),
         owned = NimbleOwnership.get_owned(@ownership_server, owner, %{}),
         overrides = Map.get(owned, @ownership_key, %{}),
         {:ok, app_overrides} <- Map.fetch(overrides, app) do
      {:ok, app_overrides}
    else
      _ -> :error
    end
  end

  defp fetch_owner do
    case NimbleOwnership.fetch_owner(@ownership_server, callers(), @ownership_key) do
      {:ok, owner} -> {:ok, owner}
      _ -> :error
    end
  end

  defp callers do
    [self() | Process.get(:"$callers", [])]
  end

  defp apply_overrides(env, overrides) do
    Enum.reduce(overrides, env, fn
      {key, {:value, value}}, acc -> Map.put(acc, key, value)
      {key, :deleted}, acc -> Map.delete(acc, key)
    end)
  end

  defp fetch_env_failed_reason(app, key) do
    case :application.get_key(app, :vsn) do
      {:ok, _} -> "because configuration at #{inspect(key)} was not set"
      :undefined -> "because the application was not loaded nor configured"
    end
  end
end
