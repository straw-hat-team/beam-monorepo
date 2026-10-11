defmodule Trogon.Test.Application do
  @moduledoc """
  A Mox behaviour for the `Application` environment functions, with
  `Trogon.Test.Application.Mock` as its mock and helpers that expect a read and
  assert on what it was given.

  `Application.put_env/3` writes to the application controller's table, the same
  global, node-wide state every process reads from with `Application.get_env/2,3`.
  A test that calls it changes what every other test concurrently running reads,
  not only its own, so the test cannot run `async: true`, and the `on_exit` that
  restores the previous value races whatever else reads or writes the same key
  while it runs. A Mox expectation belongs to the test process instead, so it
  never leaves the test that set it.

  A project reads configuration through a facade it compiles in, `Application` in
  every environment but test:

      defmodule MyApp.Config do
        @application Application.compile_env(:my_app, [MyApp, :application], Application)

        defdelegate get_env(app, key, default \\\\ nil), to: @application
      end

  and in `config/test.exs`:

      config :my_app, MyApp, application: Trogon.Test.Application.Mock

  Each test stubs the mock to read the real `Application`, expects the reads it
  cares about with what they return, and asserts on what they were given:

      import Mox

      require Trogon.Test.Application

      setup :verify_on_exit!
      setup {Trogon.Test.Application, :stub}

      test "charges the configured tax rate" do
        Trogon.Test.Application.expect_get_env(times: 1, returns: 0.07)

        tax_rate = MyApp.Billing.tax_rate()

        assert tax_rate == 0.07
        Trogon.Test.Application.assert_received_get_env(:my_app, :tax_rate)
      end

  Every `expect_*` function takes:

    * `:returns` - the value the expected call returns. Required.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  An expectation covers every call to its function, whatever key it reads, so
  expect each read the code under test makes through that function. A call past
  `:times` raises `Mox.UnexpectedCallError`. Functions with no expectation keep
  reading the real `Application` through the stub. Each expected call is
  recorded in the mailbox of the test that set it, for the matching
  `assert_received_*` macro, which needs `require Trogon.Test.Application`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Mox.allow(Trogon.Test.Application.Mock, self(), pid)`.

  > #### Do not alias this module without `as:` {: .warning}
  >
  > `alias Trogon.Test.Application` shadows the real `Application` module for
  > the rest of that file. Give it another name instead:
  >
  >     alias Trogon.Test.Application, as: TestApplication
  """

  alias Trogon.Test.Expectation

  @type app :: Application.app()
  @type key :: Application.key()
  @type value :: Application.value()

  @typedoc "Options every `expect_*` function takes."
  @type expect_opts :: [returns: term(), times: non_neg_integer()]

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
    Mox.stub_with(__MODULE__.Mock, __MODULE__.Real)
    :ok
  end

  @doc """
  Expects `get_env/3` on the mock, returning `opts[:returns]`.
  """
  @spec expect_get_env(expect_opts()) :: module()
  def expect_get_env(opts) do
    owner = self()
    value = Expectation.returns!(opts)

    Mox.expect(
      __MODULE__.Mock,
      :get_env,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:get_env, [&1, &2, &3]}, value)
    )
  end

  @doc """
  Expects `fetch_env/2` on the mock, returning `opts[:returns]`, either
  `{:ok, value}` or `:error`.
  """
  @spec expect_fetch_env(expect_opts()) :: module()
  def expect_fetch_env(opts) do
    owner = self()
    result = Expectation.returns!(opts)

    Mox.expect(
      __MODULE__.Mock,
      :fetch_env,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:fetch_env, [&1, &2]}, result)
    )
  end

  @doc """
  Expects `fetch_env!/2` on the mock, returning `opts[:returns]`.
  """
  @spec expect_fetch_env!(expect_opts()) :: module()
  def expect_fetch_env!(opts) do
    owner = self()
    value = Expectation.returns!(opts)

    Mox.expect(
      __MODULE__.Mock,
      :fetch_env!,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:fetch_env!, [&1, &2]}, value)
    )
  end

  @doc """
  Expects `get_all_env/1` on the mock, returning `opts[:returns]`.
  """
  @spec expect_get_all_env(expect_opts()) :: module()
  def expect_get_all_env(opts) do
    owner = self()
    env = Expectation.returns!(opts)

    Mox.expect(
      __MODULE__.Mock,
      :get_all_env,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:get_all_env, [&1]}, env)
    )
  end

  @doc """
  Asserts an expected `get_env/3` call read `key` from `app`, whatever default
  it passed.
  """
  defmacro assert_received_get_env(app, key) do
    quote bind_quoted: [app: app, key: key] do
      ExUnit.Assertions.assert_received({Trogon.Test.Application, {:get_env, [^app, ^key, _default]}})
    end
  end

  @doc """
  Asserts an expected `get_env/3` call read `key` from `app` with `default`.
  """
  defmacro assert_received_get_env(app, key, default) do
    quote bind_quoted: [app: app, key: key, default: default] do
      ExUnit.Assertions.assert_received({Trogon.Test.Application, {:get_env, [^app, ^key, ^default]}})
    end
  end

  @doc """
  Asserts an expected `fetch_env/2` call read `key` from `app`.
  """
  defmacro assert_received_fetch_env(app, key) do
    quote bind_quoted: [app: app, key: key] do
      ExUnit.Assertions.assert_received({Trogon.Test.Application, {:fetch_env, [^app, ^key]}})
    end
  end

  @doc """
  Asserts an expected `fetch_env!/2` call read `key` from `app`.
  """
  defmacro assert_received_fetch_env!(app, key) do
    quote bind_quoted: [app: app, key: key] do
      ExUnit.Assertions.assert_received({Trogon.Test.Application, {:fetch_env!, [^app, ^key]}})
    end
  end

  @doc """
  Asserts an expected `get_all_env/1` call read `app`.
  """
  defmacro assert_received_get_all_env(app) do
    quote bind_quoted: [app: app] do
      ExUnit.Assertions.assert_received({Trogon.Test.Application, {:get_all_env, [^app]}})
    end
  end
end

defmodule Trogon.Test.Application.Real do
  @moduledoc false
  @behaviour Trogon.Test.Application

  @impl true
  defdelegate get_env(app, key, default), to: Application

  @impl true
  defdelegate fetch_env(app, key), to: Application

  @impl true
  defdelegate fetch_env!(app, key), to: Application

  @impl true
  defdelegate get_all_env(app), to: Application
end

Mox.defmock(Trogon.Test.Application.Mock,
  for: Trogon.Test.Application,
  moduledoc: """
  The Mox mock for `Trogon.Test.Application`.

  Stub it with `Trogon.Test.Application.stub/1`, then expect reads with the
  `Trogon.Test.Application` `expect_*` functions.
  """
)
