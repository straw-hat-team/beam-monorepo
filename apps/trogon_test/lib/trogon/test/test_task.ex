defmodule Trogon.Test.TestTask do
  @moduledoc """
  Helpers for `Trogon.Test.MockTask`, the Mox mock of tasks, that expect a
  call.

  Code that calls `Task.async/1` directly gives a test no way to assert that
  the work went async, or how many tasks it started. Start tasks through a
  facade the project compiles in, `Task` in every environment but test:

      defmodule MyApp do
        @task Application.compile_env(:my_app, [__MODULE__, :task], Task)

        defdelegate async(fun), to: @task
      end

  and in `config/test.exs`:

      config :my_app, MyApp, task: Trogon.Test.MockTask

  The code under test keeps calling `Task.await/2`, `Task.yield/2`, and the rest
  of `Task` directly, since every call returns a real `Task`.

  `use Trogon.Test` stubs the mock to start real tasks. An expected `async/1`
  starts a real task too, running the function it was given, and Mox fails the
  test when it exits if the code under test did not go async as many times as
  expected:

      use Trogon.Test

      test "charges the card in the background" do
        TestTask.expect_async(times: 1)

        assert MyApp.Billing.checkout() == {:ok, :charged}
      end

  `expect_async/1` takes `:times`, how many calls the expectation covers,
  `1` by default. A call past `:times` raises `Mox.UnexpectedCallError`. The
  test asserts on what the function did, not on the function itself, so an
  expected call is not recorded for an `assert_received_*` macro.

  The function runs with the caller in its `$callers`, so the mocks it calls
  reach the test's expectations, as with `Task.async/1`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`. The task belongs to whichever process
  called the mock, so only that process can await it, as with `Task.async/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockTask

  @typedoc "Options `expect_async/1` takes."
  @type expect_opts :: [times: non_neg_integer()]

  @doc """
  Stubs `Trogon.Test.MockTask` to start real tasks.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestTask, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockTask, __MODULE__.ElixirTask)
    :ok
  end

  @doc """
  Expects `async/1` on the mock, starting a real task that runs the function
  it was given.
  """
  @spec expect_async(expect_opts()) :: module()
  def expect_async(opts \\ []) do
    Mox.expect(MockTask, :async, Expectation.times(opts), fn fun when is_function(fun, 0) -> Task.async(fun) end)
  end
end
