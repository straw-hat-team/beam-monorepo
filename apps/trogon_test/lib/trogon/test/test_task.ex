defmodule Trogon.Test.TestTask do
  @moduledoc """
  Helpers for `Trogon.Test.MockTask`, the Mox mock of tasks, that expect a
  call.

  Code that calls `Task.async/1` or `Task.async_stream/3` directly gives a test
  no way to assert that the work went async, how many times, or with which
  concurrency options. Start tasks through a facade the project compiles in,
  `Task` in every environment but test:

      defmodule MyApp do
        @task Application.compile_env(:my_app, [__MODULE__, :task], Task)

        defdelegate async(fun), to: @task
        defdelegate async_stream(enumerable, fun, opts \\\\ []), to: @task
      end

  and in `config/test.exs`:

      config :my_app, MyApp, task: Trogon.Test.MockTask

  The mock has `async_stream/3` and no `async_stream/2`, so the facade always
  passes options, as the one above does through its default argument. The code
  under test keeps calling `Task.await/2`, `Task.yield/2`, and the rest of
  `Task` directly, since every call returns real tasks.

  `use Trogon.Test` stubs the mock to start real tasks. An expected call starts
  real tasks too, running the function it was given, and Mox fails the test
  when it exits if the code under test did not make the call as many times as
  expected:

      use Trogon.Test

      test "charges every cart in parallel" do
        TestTask.expect_async_stream(times: 1)

        assert MyApp.Billing.checkout_all() == [{:ok, :charged}]

        TestTask.assert_received_async_stream(max_concurrency: 4)
        Trogon.Test.assert_empty_mailbox()
      end

  Every `expect_*` function takes `:times`, how many calls the expectation
  covers, `1` by default. A call past `:times` raises `Mox.UnexpectedCallError`.

  The test asserts on what the function did, not on the function itself, so an
  expected `async/1` is not recorded. An expected `async_stream/3` records the
  options it was given in the mailbox of the test that set it, for
  `assert_received_async_stream/1`.

  The function runs with the caller in its `$callers`, so the mocks it calls
  reach the test's expectations, as with `Task.async/1`. The expectations reach
  the test's `$callers`, such as a `Task`, and a process allowed with
  `Trogon.Test.allow/1`. The tasks belong to whichever process called the
  mock, so only that process can await them, as with `Task`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockTask
  alias Trogon.Test.Recorder

  @typedoc "Options every `expect_*` function takes."
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

  @doc """
  Expects `async_stream/3` on the mock, streaming real tasks that run the
  function it was given.
  """
  @spec expect_async_stream(expect_opts()) :: module()
  def expect_async_stream(opts \\ []) do
    recorder = Recorder.new()

    Mox.expect(MockTask, :async_stream, Expectation.times(opts), &record_async_stream(recorder, &1, &2, &3))
  end

  @doc """
  Asserts an expected `async_stream/3` call was given `opts`.
  """
  defmacro assert_received_async_stream(opts) do
    quote bind_quoted: [opts: opts] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestTask, {:async_stream, [^opts]}}})
      )
    end
  end

  defp record_async_stream(recorder, enumerable, fun, opts) when is_function(fun, 1) and is_list(opts) do
    Expectation.record(recorder, __MODULE__, {:async_stream, [opts]}, Task.async_stream(enumerable, fun, opts))
  end
end
