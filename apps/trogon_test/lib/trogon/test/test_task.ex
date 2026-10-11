defmodule Trogon.Test.TestTask do
  @moduledoc """
  Helpers for `Trogon.Test.MockTask`, the Mox mock of tasks, that expect a
  call.

  Code that calls `Task.async/1`, `Task.await/2`, or `Task.async_stream/3`
  directly gives a test no way to assert that the work went async, how long it
  waits for it, or with which concurrency options, and a test of what it does
  when a task times out has to wait the whole timeout. Start and await tasks
  through a facade the project compiles in, `Task` in every environment but
  test:

      defmodule MyApp do
        @task Application.compile_env(:my_app, [__MODULE__, :task], Task)

        defdelegate async(fun), to: @task
        defdelegate await(task, timeout \\\\ 5000), to: @task
        defdelegate async_stream(enumerable, fun, opts \\\\ []), to: @task
      end

  and in `config/test.exs`:

      config :my_app, MyApp, task: Trogon.Test.MockTask

  The mock has `await/2` and `async_stream/3` and no `await/1` or
  `async_stream/2`, so the facade always passes a timeout and options, as the
  one above does through its default arguments. The code under test keeps
  calling `Task.yield/2` and the rest of `Task` directly, since every call
  returns real tasks.

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

  `expect_await_timeout/1` makes `await/2` exit the way `Task.await/2` does when
  the task runs past its timeout, without waiting for it:

      test "gives up on a slow quote" do
        TestTask.expect_async(times: 1)
        TestTask.expect_await_timeout(times: 1)

        assert MyApp.Pricing.quote() == {:error, :timeout}

        TestTask.assert_received_await(2_000)
        Trogon.Test.assert_empty_mailbox()
      end

  The test asserts on what the function did, not on the function itself, so an
  expected `async/1` is not recorded. An expected `await/2` records the timeout
  it was given, and an expected `async_stream/3` the options, in the mailbox of
  the test that set it, for `assert_received_await/1` and
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

  defguardp is_timeout(timeout) when timeout == :infinity or (is_integer(timeout) and timeout >= 0)

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
  Expects `await/2` on the mock, awaiting the real task.
  """
  @spec expect_await(expect_opts()) :: module()
  def expect_await(opts \\ []) do
    recorder = Recorder.new()

    Mox.expect(MockTask, :await, Expectation.times(opts), fn %Task{} = task, timeout when is_timeout(timeout) ->
      Expectation.record(recorder, __MODULE__, {:await, [timeout]}, Task.await(task, timeout))
    end)
  end

  @doc """
  Expects `await/2` on the mock, exiting right away as `Task.await/2` does when
  the task runs past the timeout.

  The task keeps running and its reply is dropped, as after a real timeout. A
  call given `:infinity`, which never times out, raises `ArgumentError`.
  """
  @dialyzer {:no_return, expect_await_timeout: 1}
  @spec expect_await_timeout(expect_opts()) :: module()
  def expect_await_timeout(opts \\ []) do
    recorder = Recorder.new()

    Mox.expect(MockTask, :await, Expectation.times(opts), fn %Task{} = task, timeout when is_timeout(timeout) ->
      time_out!(recorder, task, timeout)
    end)
  end

  @doc """
  Asserts an expected `await/2` call was given `timeout`.
  """
  defmacro assert_received_await(timeout) do
    quote bind_quoted: [timeout: timeout] do
      Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestTask, {:await, [^timeout]}}}))
    end
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

  defp time_out!(_recorder, _task, :infinity) do
    raise ArgumentError, "Task.await/2 never times out when given :infinity"
  end

  defp time_out!(recorder, %Task{ref: ref, owner: owner} = task, timeout) do
    if owner != self() do
      raise ArgumentError,
            "task #{inspect(task)} must be queried from the owner but was queried from #{inspect(self())}"
    end

    Process.demonitor(ref, [:flush])
    Expectation.record(recorder, __MODULE__, {:await, [timeout]}, :timeout)
    exit({:timeout, {Task, :await, [task, timeout]}})
  end

  defp record_async_stream(recorder, enumerable, fun, opts) when is_function(fun, 1) and is_list(opts) do
    Expectation.record(recorder, __MODULE__, {:async_stream, [opts]}, Task.async_stream(enumerable, fun, opts))
  end
end
