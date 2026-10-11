defmodule Trogon.Test.TestTask do
  @moduledoc """
  Helpers for `Trogon.Test.MockTask`, the Mox mock of tasks, that expect a call
  and assert on what it was given.

  Code that calls `Task.async/1` directly runs the side effect inside the task
  in every test, so a test can neither control what the task returns nor keep
  the side effect from happening. Start tasks through a facade the project
  compiles in, `Task` in every environment but test:

      defmodule MyApp do
        @task Application.compile_env(:my_app, [__MODULE__, :task], Task)

        defdelegate async(fun), to: @task
      end

  and in `config/test.exs`:

      config :my_app, MyApp, task: Trogon.Test.MockTask

  The code under test keeps calling `Task.await/2`, `Task.yield/2`, and the rest
  of `Task` directly, since every call returns a real `Task`.

  `use Trogon.Test` stubs the mock to start real tasks. An expected
  `async/1` never runs the function it is given. It returns a real task that
  completes with `:returns` instead, and records the function, so the test can
  run it itself when it wants the side effect:

      use Trogon.Test

      test "charges the card in the background" do
        TestTask.expect_async(times: 1, returns: {:ok, :charged})

        assert MyApp.Billing.checkout() == {:ok, :charged}

        charge = TestTask.assert_received_async()
        assert charge.() == {:ok, :charged}
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_async/1` takes:

    * `:returns` - the result the task completes with. Required.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for `assert_received_async/0`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`. The task belongs to whichever process
  called the mock, so only that process can await it, as with `Task.async/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockTask
  alias Trogon.Test.Recorder

  @typedoc "Options `expect_async/1` takes."
  @type expect_opts :: [returns: term(), times: non_neg_integer()]

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
  Expects `async/1` on the mock without running the function it is given,
  returning a task that completes with `opts[:returns]`.
  """
  @spec expect_async(expect_opts()) :: module()
  def expect_async(opts) do
    recorder = Recorder.new()
    result = Expectation.returns!(opts)

    Mox.expect(MockTask, :async, Expectation.times(opts), fn fun when is_function(fun, 0) ->
      Expectation.record(recorder, __MODULE__, {:async, [fun]}, Task.async(fn -> result end))
    end)
  end

  @doc """
  Asserts an expected `async/1` call was made, and returns the function it was
  given so the test can run it.
  """
  defmacro assert_received_async do
    quote do
      {Trogon.Test, {Trogon.Test.TestTask, {:async, [fun]}}} =
        Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestTask, {:async, [_fun]}}}))

      fun
    end
  end
end
