defmodule Trogon.Test.TestProcess do
  @moduledoc """
  A Mox behaviour for scheduling messages, with `Trogon.Test.MockProcess` as its
  mock and helpers that expect a schedule and assert on what it was given.

  Code that calls `Process.send_after/4` directly makes a test wait for the
  timer, or race it. Schedule through a facade the project compiles in,
  `Process` in every environment but test:

      defmodule MyApp.Timer do
        @process Application.compile_env(:my_app, [__MODULE__, :process], Process)

        defdelegate send_after(dest, msg, time, opts \\\\ []), to: @process
      end

  and in `config/test.exs`:

      config :my_app, MyApp.Timer, process: Trogon.Test.MockProcess

  Each test stubs the mock to schedule for real, expects the schedules it cares
  about, and asserts on what they were given. The expected message is never
  sent, so the test sends it itself when it wants the timer to fire:

      import Mox

      require Trogon.Test
      require Trogon.Test.TestProcess

      setup :verify_on_exit!
      setup {Trogon.Test.TestProcess, :stub}

      test "schedules the next poll" do
        Trogon.Test.TestProcess.expect_send_after(times: 1)

        poller = start_supervised!(MyApp.Poller)

        Trogon.Test.TestProcess.assert_received_send_after(poller, :poll, 5_000)
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_send_after/1` takes:

    * `:returns` - the timer reference the expected call returns. Defaults to a
      new reference.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_send_after/3,4`, macros that need
  `require Trogon.Test.TestProcess`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockProcess

  @typedoc "Options `expect_send_after/1` takes."
  @type expect_opts :: [returns: reference(), times: non_neg_integer()]

  @callback send_after(dest :: pid() | atom(), msg :: term(), time :: non_neg_integer(), opts :: keyword()) ::
              reference()

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
  @spec expect_send_after(expect_opts()) :: module()
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
end
