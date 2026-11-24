defmodule Trogon.Test.TestApplication do
  @moduledoc """
  Helpers for `Trogon.Test.MockApplication`, the Mox mock of the `Application`
  environment functions, that expect a read and assert on what it was given.

  `Application.put_env/3` writes to the application controller's table, the same
  global, node-wide state every process reads from with `Application.get_env/2,3`.
  A test that calls it changes what every other test concurrently running reads,
  not only its own, so the test cannot run `async: true`, and the `on_exit` that
  restores the previous value races whatever else reads or writes the same key
  while it runs. A Mox expectation belongs to the test process instead, so it
  never leaves the test that set it.

  A project reads configuration through a facade it compiles in, `Application` in
  every environment but test:

      defmodule MyApp do
        @application Application.compile_env(:my_app, [__MODULE__, :application], Application)

        defdelegate get_env(app, key, default \\\\ nil), to: @application
      end

  and in `config/test.exs`:

      config :my_app, MyApp, application: Trogon.Test.MockApplication

  The mock has `get_env/3` and no `get_env/2`, so the facade always passes a
  default, as the one above does through its default argument.

  `use Trogon.Test` stubs the mock to read the real `Application`. Each test
  expects the reads it cares about with what they return, and asserts on what
  they were given:

      use Trogon.Test

      test "charges the configured tax rate" do
        TestApplication.expect_get_env(times: 1, returns: 0.07)

        tax_rate = MyApp.Billing.tax_rate()

        assert tax_rate == 0.07
        TestApplication.assert_received_get_env(:my_app, :tax_rate)
        Trogon.Test.assert_empty_mailbox()
      end

  Every `expect_*` function takes:

    * `:returns` - the value the expected call returns. Required.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  An expectation covers every call to its function, whatever key it reads, so
  expect each read the code under test makes through that function. A call past
  `:times` raises `Mox.UnexpectedCallError`. Functions with no expectation keep
  reading the real `Application` through the stub. Each expected call is
  recorded in the mailbox of the test that set it, for the matching
  `assert_received_*` macro.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.

  ## Overriding one key

  An expectation covers every call to its function, so it cannot change one key
  while the code under test also reads others. `stub_env/3` overrides only the
  `{app, key}` it is given and leaves every other read on the real
  `Application`. Give it a function to change the real value, or a value to
  replace it:

      test "charges the configured tax rate" do
        TestApplication.stub_env(:acme, Acme.Billing, &Keyword.merge(&1, tax_rate: 0.07))

        assert Acme.Billing.tax_rate() == 0.07
      end

  The override applies to `get_env/3`, `fetch_env/2`, `fetch_env!/2` and
  `get_all_env/1`. A stub is not an expectation, so reads it serves are not
  recorded. To assert a read happened, use `expect_get_env/1` and
  `assert_received_get_env/2`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockApplication
  alias Trogon.Test.Recorder
  alias Trogon.Test.TestApplication.ElixirApplication

  @overrides_key {__MODULE__, :env_overrides}

  @typedoc "Options every `expect_*` function takes."
  @type expect_opts :: [returns: term(), times: non_neg_integer()]

  @doc """
  Stubs `Trogon.Test.MockApplication` to read the real `Application`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestApplication, :stub}`. Drops every override of
  `stub_env/3`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Process.delete(@overrides_key)
    Mox.stub_with(MockApplication, ElixirApplication)
    :ok
  end

  @doc """
  Overrides `key` of `app` on the mock, leaving every other read on the real
  `Application`.

  `value_or_fun` is either the value to return, or a function of arity 1 that
  receives the real current value and returns the overridden one:

      TestApplication.stub_env(:acme, Acme.Billing, &Keyword.merge(&1, tax_rate: 0.07))
      TestApplication.stub_env(:acme, :region, "eu")

  A value that is itself a function is taken for a function of the real value,
  so wrap it to stub a config value that is a function:

      TestApplication.stub_env(:acme, :clock, fn _real -> &MyClock.now/0 end)

  The override covers `get_env/3` and `fetch_env/2` (`{:ok, overridden}`),
  `fetch_env!/2` and `get_all_env/1`, where the key appears with its overridden
  value. An override of an unset key returns the override. The function
  receives the real value, which for an unset key is the default the caller
  passed to `get_env/3`, and `nil` for the other functions.

  Overrides stack. Those of different keys all apply. Those of the same key
  apply in call order, each receiving the result of the previous one, so a
  later value replaces an earlier override and a later function changes it.

  An expectation answers its calls before the stub does, and the stub answers
  the calls after them, but Mox drops the stub of a function when it is expected
  after it. Call `stub_env/3` after the `expect_*` functions of the same test,
  or a call past an expectation's `:times` raises. `stub/1` drops every
  override. The overrides reach the same processes as the
  expectations: the test's `$callers` and processes allowed with
  `Trogon.Test.allow/1`.
  """
  @spec stub_env(atom(), term(), term() | (term() -> term())) :: :ok
  def stub_env(app, key, value_or_fun) when is_atom(app) do
    overrides = Process.get(@overrides_key, %{})
    overrides = Map.update(overrides, {app, key}, [to_fun(value_or_fun)], &(&1 ++ [to_fun(value_or_fun)]))
    Process.put(@overrides_key, overrides)

    install(overrides)
  end

  defp to_fun(fun) when is_function(fun, 1), do: fun
  defp to_fun(value), do: fn _real -> value end

  defp install(overrides) do
    Mox.stub(MockApplication, :get_env, fn app, key, default when is_atom(app) ->
      case Map.fetch(overrides, {app, key}) do
        {:ok, funs} -> apply_all(funs, ElixirApplication.get_env(app, key, default))
        :error -> ElixirApplication.get_env(app, key, default)
      end
    end)

    Mox.stub(MockApplication, :fetch_env, fn app, key when is_atom(app) ->
      case Map.fetch(overrides, {app, key}) do
        {:ok, funs} -> {:ok, apply_all(funs, real_or_nil(app, key))}
        :error -> ElixirApplication.fetch_env(app, key)
      end
    end)

    Mox.stub(MockApplication, :fetch_env!, fn app, key when is_atom(app) ->
      case Map.fetch(overrides, {app, key}) do
        {:ok, funs} -> apply_all(funs, real_or_nil(app, key))
        :error -> ElixirApplication.fetch_env!(app, key)
      end
    end)

    Mox.stub(MockApplication, :get_all_env, fn app when is_atom(app) ->
      for {{^app, key}, funs} <- overrides, reduce: ElixirApplication.get_all_env(app) do
        env -> List.keystore(env, key, 0, {key, apply_all(funs, Keyword.get(env, key))})
      end
    end)

    :ok
  end

  defp real_or_nil(app, key) do
    case ElixirApplication.fetch_env(app, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp apply_all(funs, real), do: Enum.reduce(funs, real, fn fun, value -> fun.(value) end)

  @doc """
  Expects `get_env/3` on the mock, returning `opts[:returns]`.
  """
  @spec expect_get_env(expect_opts()) :: module()
  def expect_get_env(opts) do
    recorder = Recorder.new()
    value = Expectation.returns!(opts)

    Mox.expect(MockApplication, :get_env, Expectation.times(opts), fn app, key, default when is_atom(app) ->
      Expectation.record(recorder, __MODULE__, {:get_env, [app, key, default]}, value)
    end)
  end

  @doc """
  Expects `fetch_env/2` on the mock, returning `opts[:returns]`, either
  `{:ok, value}` or `:error`.
  """
  @spec expect_fetch_env(expect_opts()) :: module()
  def expect_fetch_env(opts) do
    recorder = Recorder.new()
    result = Expectation.returns!(opts, &fetch_env_result?/1, "{:ok, value} or :error")

    Mox.expect(MockApplication, :fetch_env, Expectation.times(opts), fn app, key when is_atom(app) ->
      Expectation.record(recorder, __MODULE__, {:fetch_env, [app, key]}, result)
    end)
  end

  @doc """
  Expects `fetch_env!/2` on the mock, returning `opts[:returns]`.
  """
  @spec expect_fetch_env!(expect_opts()) :: module()
  def expect_fetch_env!(opts) do
    recorder = Recorder.new()
    value = Expectation.returns!(opts)

    Mox.expect(MockApplication, :fetch_env!, Expectation.times(opts), fn app, key when is_atom(app) ->
      Expectation.record(recorder, __MODULE__, {:fetch_env!, [app, key]}, value)
    end)
  end

  @doc """
  Expects `get_all_env/1` on the mock, returning `opts[:returns]`.
  """
  @spec expect_get_all_env(expect_opts()) :: module()
  def expect_get_all_env(opts) do
    recorder = Recorder.new()
    env = Expectation.returns!(opts, &Keyword.keyword?/1, "a keyword list")

    Mox.expect(MockApplication, :get_all_env, Expectation.times(opts), fn app when is_atom(app) ->
      Expectation.record(recorder, __MODULE__, {:get_all_env, [app]}, env)
    end)
  end

  defp fetch_env_result?({:ok, _value}), do: true
  defp fetch_env_result?(:error), do: true
  defp fetch_env_result?(_result), do: false

  @doc """
  Asserts an expected `get_env/3` call read `key` from `app`, whatever default
  it passed.
  """
  defmacro assert_received_get_env(app, key) do
    quote bind_quoted: [app: app, key: key] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received(
          {Trogon.Test, {Trogon.Test.TestApplication, {:get_env, [^app, ^key, _default]}}}
        )
      )
    end
  end

  @doc """
  Asserts an expected `get_env/3` call read `key` from `app` with `default`.
  """
  defmacro assert_received_get_env(app, key, default) do
    quote bind_quoted: [app: app, key: key, default: default] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received(
          {Trogon.Test, {Trogon.Test.TestApplication, {:get_env, [^app, ^key, ^default]}}}
        )
      )
    end
  end

  @doc """
  Asserts an expected `fetch_env/2` call read `key` from `app`.
  """
  defmacro assert_received_fetch_env(app, key) do
    quote bind_quoted: [app: app, key: key] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestApplication, {:fetch_env, [^app, ^key]}}})
      )
    end
  end

  @doc """
  Asserts an expected `fetch_env!/2` call read `key` from `app`.
  """
  defmacro assert_received_fetch_env!(app, key) do
    quote bind_quoted: [app: app, key: key] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestApplication, {:fetch_env!, [^app, ^key]}}})
      )
    end
  end

  @doc """
  Asserts an expected `get_all_env/1` call read `app`.
  """
  defmacro assert_received_get_all_env(app) do
    quote bind_quoted: [app: app] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestApplication, {:get_all_env, [^app]}}})
      )
    end
  end
end
