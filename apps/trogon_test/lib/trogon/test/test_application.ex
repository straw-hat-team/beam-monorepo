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
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockApplication
  alias Trogon.Test.Recorder

  @typedoc "Options every `expect_*` function takes."
  @type expect_opts :: [returns: term(), times: non_neg_integer()]

  @doc """
  Stubs `Trogon.Test.MockApplication` to read the real `Application`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestApplication, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockApplication, __MODULE__.ElixirApplication)
    :ok
  end

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
