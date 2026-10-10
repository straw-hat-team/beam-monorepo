defmodule Trogon.Test.Application do
  @moduledoc """
  A Mox behaviour for the `Application` environment functions, with
  `Trogon.Test.Application.Mock` as its mock and helpers that override config
  for a single test.

  `Application.put_env/3` writes to the application controller's table, the same
  global, node-wide state every process reads from with `Application.get_env/2,3`.
  A test that calls it changes what every other test concurrently running reads,
  not only its own, so the test cannot run `async: true`, and the `on_exit` that
  restores the previous value races whatever else reads or writes the same key
  while it runs. A Mox stub belongs to the test process instead, so an override
  never leaves the test that made it.

  A project reads configuration through a facade it compiles in, `Application` in
  every environment but test:

      defmodule MyApp.Config do
        @application Application.compile_env(:my_app, [MyApp, :application], Application)

        defdelegate get_env(app, key, default \\\\ nil), to: @application
      end

  and in `config/test.exs`:

      config :my_app, MyApp, application: Trogon.Test.Application.Mock

  Each test stubs the mock to read the real `Application`, then overrides the
  config it cares about:

      setup {Trogon.Test.Application, :stub}

      test "charges the configured tax rate" do
        Trogon.Test.Application.put_env(:my_app, :tax_rate, 0.07)
        assert MyApp.Billing.tax_rate() == 0.07
      end

  The overrides are Mox stubs, so they reach the test's `$callers`, such as a
  `Task`, and a process allowed with
  `Mox.allow(Trogon.Test.Application.Mock, self(), pid)`. Call the write
  functions from the test process itself, since a stub set from any other
  process belongs to that process.

  > #### Do not alias this module without `as:` {: .warning}
  >
  > `alias Trogon.Test.Application` shadows the real `Application` module for
  > the rest of that file. Give it another name instead:
  >
  >     alias Trogon.Test.Application, as: TestApplication
  """

  @overrides_key {__MODULE__, :overrides}

  @type app :: Application.app()
  @type key :: Application.key()
  @type value :: Application.value()

  @callback get_env(app(), key()) :: value()
  @callback get_env(app(), key(), value()) :: value()
  @callback fetch_env(app(), key()) :: {:ok, value()} | :error
  @callback fetch_env!(app(), key()) :: value()
  @callback get_all_env(app()) :: [{key(), value()}]

  @doc """
  Stubs `Trogon.Test.Application.Mock` to read the real `Application`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.Application, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Process.delete(@overrides_key)
    stub_overrides(%{})
  end

  @doc """
  Puts `value` in `key` for `app`, for the calling test alone.

  Same semantics as `Application.put_env/3`: `value` replaces whatever `key`
  held before.
  """
  @spec put_env(app(), key(), value()) :: :ok
  def put_env(app, key, value) do
    update_override(app, key, fn _current -> {:value, value} end)
  end

  @doc """
  Deep merges `value` onto the current value of `key` in `app`, for the calling
  test alone.

  Merges with `Config.Reader.merge/2`, the function `mix` uses to merge
  configuration files: keyword lists merge recursively, and any other value is
  replaced outright.
  """
  @spec merge_env(app(), key(), value()) :: :ok
  def merge_env(app, key, value) do
    update_override(app, key, fn current ->
      merged = Config.Reader.merge([{app, current_env(app, key, current)}], [{app, [{key, value}]}])
      {:value, get_in(merged, [app, key])}
    end)
  end

  @doc """
  Makes `key` in `app` read as missing, for the calling test alone.
  """
  @spec delete_env(app(), key()) :: :ok
  def delete_env(app, key) do
    update_override(app, key, fn _current -> :deleted end)
  end

  defp current_env(_app, key, {:value, value}), do: [{key, value}]
  defp current_env(_app, _key, :deleted), do: []

  defp current_env(app, key, nil) do
    case Application.fetch_env(app, key) do
      {:ok, value} -> [{key, value}]
      :error -> []
    end
  end

  defp update_override(app, key, fun) do
    overrides = Process.get(@overrides_key, %{})
    current = get_in(overrides, [Access.key(app, %{}), key])
    overrides = put_in(overrides, [Access.key(app, %{}), key], fun.(current))
    Process.put(@overrides_key, overrides)
    stub_overrides(overrides)
  end

  defp stub_overrides(overrides) do
    __MODULE__.Mock
    |> Mox.stub(:get_env, &get_env(overrides, &1, &2, nil))
    |> Mox.stub(:get_env, &get_env(overrides, &1, &2, &3))
    |> Mox.stub(:fetch_env, &fetch_env(overrides, &1, &2))
    |> Mox.stub(:fetch_env!, fn app, key ->
      case fetch_override(overrides, app, key) do
        {:ok, value} ->
          value

        :deleted ->
          raise ArgumentError,
                "could not fetch application environment #{inspect(key)} for application " <>
                  "#{inspect(app)} because configuration at #{inspect(key)} was not set"

        :error ->
          Application.fetch_env!(app, key)
      end
    end)
    |> Mox.stub(:get_all_env, fn app ->
      overrides
      |> Map.get(app, %{})
      |> Enum.reduce(Map.new(Application.get_all_env(app)), fn
        {key, {:value, value}}, env -> Map.put(env, key, value)
        {key, :deleted}, env -> Map.delete(env, key)
      end)
      |> Enum.to_list()
    end)

    :ok
  end

  defp get_env(overrides, app, key, default) do
    case fetch_override(overrides, app, key) do
      {:ok, value} -> value
      :deleted -> default
      :error -> Application.get_env(app, key, default)
    end
  end

  defp fetch_env(overrides, app, key) do
    case fetch_override(overrides, app, key) do
      {:ok, value} -> {:ok, value}
      :deleted -> :error
      :error -> Application.fetch_env(app, key)
    end
  end

  defp fetch_override(overrides, app, key) do
    case overrides |> Map.get(app, %{}) |> Map.fetch(key) do
      {:ok, {:value, value}} -> {:ok, value}
      {:ok, :deleted} -> :deleted
      :error -> :error
    end
  end
end

Mox.defmock(Trogon.Test.Application.Mock,
  for: Trogon.Test.Application,
  moduledoc: """
  The Mox mock for `Trogon.Test.Application`.

  Stub it with `Trogon.Test.Application.stub/1`, then override keys with
  `Trogon.Test.Application.put_env/3`, `Trogon.Test.Application.merge_env/3`, and
  `Trogon.Test.Application.delete_env/2`.
  """
)
