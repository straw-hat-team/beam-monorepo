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
    put_override(app, key, {:value, value})
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
    current = overrides() |> fetch_override(app, key) |> current_env(app, key)
    merged = Config.Reader.merge([{app, current}], [{app, [{key, value}]}])
    put_override(app, key, {:value, get_in(merged, [app, key])})
  end

  @doc """
  Makes `key` in `app` read as missing, for the calling test alone.

  `fetch_env!/2` on the mock then raises `Trogon.Test.Application.MissingEnvError`.
  """
  @spec delete_env(app(), key()) :: :ok
  def delete_env(app, key) do
    put_override(app, key, :deleted)
  end

  defp current_env({:ok, value}, _app, key), do: [{key, value}]
  defp current_env(:deleted, _app, _key), do: []

  defp current_env(:error, app, key) do
    case Application.fetch_env(app, key) do
      {:ok, value} -> [{key, value}]
      :error -> []
    end
  end

  defp overrides, do: Process.get(@overrides_key, %{})

  defp put_override(app, key, override) do
    overrides = put_in(overrides(), [Access.key(app, %{}), key], override)
    Process.put(@overrides_key, overrides)
    stub_overrides(overrides)
  end

  defp stub_overrides(overrides) do
    __MODULE__.Mock
    |> Mox.stub(:get_env, &get_env(overrides, &1, &2, nil))
    |> Mox.stub(:get_env, &get_env(overrides, &1, &2, &3))
    |> Mox.stub(:fetch_env, &fetch_env(overrides, &1, &2))
    |> Mox.stub(:fetch_env!, &fetch_env!(overrides, &1, &2))
    |> Mox.stub(:get_all_env, &get_all_env(overrides, &1))

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

  defp fetch_env!(overrides, app, key) do
    case fetch_override(overrides, app, key) do
      {:ok, value} -> value
      :deleted -> raise __MODULE__.MissingEnvError, app: app, key: key
      :error -> Application.fetch_env!(app, key)
    end
  end

  defp get_all_env(overrides, app) do
    overrides
    |> Map.get(app, %{})
    |> Enum.reduce(Map.new(Application.get_all_env(app)), &apply_override/2)
    |> Enum.to_list()
  end

  defp apply_override({key, {:value, value}}, env), do: Map.put(env, key, value)
  defp apply_override({key, :deleted}, env), do: Map.delete(env, key)

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
