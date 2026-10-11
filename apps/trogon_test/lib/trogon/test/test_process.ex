defmodule Trogon.Test.TestProcess do
  @moduledoc """
  A Mox behaviour for timers, scheduled messages and sleeps, with
  `Trogon.Test.MockProcess` as its mock and helpers that expect a call and
  assert on what it was given.

  Code that calls `Process.send_after/4` or `Process.sleep/1` directly makes a
  test wait for the timer, or race it. Call them through a facade the project
  compiles in, `Process` in every environment but test:

      defmodule MyApp.Timer do
        @process Application.compile_env(:my_app, [__MODULE__, :process], Process)

        defdelegate send_after(dest, msg, time, opts \\\\ []), to: @process
        defdelegate sleep(timeout), to: @process
      end

  and in `config/test.exs`:

      config :my_app, MyApp.Timer, process: Trogon.Test.MockProcess

  `use Trogon.Test` stubs the mock to call the real `Process`. Each test expects
  the calls it cares about, and asserts on what they were given. An expected
  `send_after/4` never sends its message, so the test sends it itself when it
  wants the timer to fire:

      use Trogon.Test

      test "schedules the next poll" do
        TestProcess.expect_send_after(times: 1)

        poller = start_supervised!(MyApp.Poller)

        TestProcess.assert_received_send_after(poller, :poll, 5_000)
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_send_after/1` takes:

    * `:returns` - the timer reference the expected call returns. Defaults to a
      new reference.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  `expect_sleep/1` takes `:times` and returns `:ok` without sleeping.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_send_after/3,4` and `assert_received_sleep/1`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockProcess

  @typedoc "Options `expect_send_after/1` takes."
  @type send_after_opts :: [returns: reference(), times: non_neg_integer()]

  @typedoc "Options `expect_sleep/1` takes."
  @type sleep_opts :: [times: non_neg_integer()]

  @callback send_after(dest :: pid() | atom(), msg :: term(), time :: non_neg_integer(), opts :: keyword()) ::
              reference()

  @callback sleep(timeout :: timeout()) :: :ok

  @doc """
  Stubs `Trogon.Test.MockProcess` to schedule with the real `Process`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestProcess, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockProcess, __MODULE__.ElixirProcess)
    :ok
  end

  @doc """
  Expects `send_after/4` on the mock without scheduling the message, returning
  `opts[:returns]`.
  """
  @spec expect_send_after(send_after_opts()) :: module()
  def expect_send_after(opts \\ []) do
    owner = self()
    timer = Keyword.get_lazy(opts, :returns, &make_ref/0)

    Mox.expect(
      MockProcess,
      :send_after,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:send_after, [&1, &2, &3, &4]}, timer)
    )
  end

  @doc """
  Expects `sleep/1` on the mock, returning `:ok` without sleeping.
  """
  @spec expect_sleep(sleep_opts()) :: module()
  def expect_sleep(opts \\ []) do
    owner = self()

    Mox.expect(
      MockProcess,
      :sleep,
      Expectation.times(opts),
      &Expectation.record(owner, __MODULE__, {:sleep, [&1]}, :ok)
    )
  end

  @doc """
  Asserts an expected `send_after/4` call scheduled `msg` to `dest` after
  `time`, whatever options it was given.
  """
  defmacro assert_received_send_after(dest, msg, time) do
    quote bind_quoted: [dest: dest, msg: msg, time: time] do
      ExUnit.Assertions.assert_received(
        {Trogon.Test, {Trogon.Test.TestProcess, {:send_after, [^dest, ^msg, ^time, _opts]}}}
      )
    end
  end

  @doc """
  Asserts an expected `send_after/4` call scheduled `msg` to `dest` after
  `time` with `opts`.
  """
  defmacro assert_received_send_after(dest, msg, time, opts) do
    quote bind_quoted: [dest: dest, msg: msg, time: time, opts: opts] do
      ExUnit.Assertions.assert_received(
        {Trogon.Test, {Trogon.Test.TestProcess, {:send_after, [^dest, ^msg, ^time, ^opts]}}}
      )
    end
  end

  @doc """
  Asserts an expected `sleep/1` call was given `timeout`.
  """
  defmacro assert_received_sleep(timeout) do
    quote bind_quoted: [timeout: timeout] do
      ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestProcess, {:sleep, [^timeout]}}})
    end
  end
end
