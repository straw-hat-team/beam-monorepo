defmodule Trogon.Test.TestRand do
  @moduledoc """
  Helpers for `Trogon.Test.MockRand`, the Mox mock of random numbers, that
  expect a draw and assert on what it was given.

  Code that calls `:rand.uniform/1` directly draws a different number on every
  run, so a test cannot pin the branch it takes, such as a retry jitter. Draw
  through a facade the project compiles in, `:rand` in every environment but
  test:

      defmodule MyApp do
        @rand Application.compile_env(:my_app, [__MODULE__, :rand], :rand)

        defdelegate uniform(n), to: @rand
      end

  and in `config/test.exs`:

      config :my_app, MyApp, rand: Trogon.Test.MockRand

  `use Trogon.Test` stubs the mock to draw from the real `:rand`. Each test
  expects the draws it cares about with what they return, and asserts on what
  they were given:

      use Trogon.Test

      test "waits a jittered backoff before retrying" do
        TestRand.expect_uniform(times: 1, returns: 250)

        assert MyApp.Retry.backoff(1) == 1_250

        TestRand.assert_received_uniform(1_000)
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_uniform/1` takes:

    * `:returns` - the integer every expected call returns. Required. It must
      be a positive integer, and a call given an `n` below it raises
      `ArgumentError`, since `:rand.uniform/1` only returns from `1` to `n`.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_uniform/1`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockRand
  alias Trogon.Test.Recorder

  @typedoc "Options `expect_uniform/1` takes."
  @type expect_opts :: [returns: pos_integer(), times: non_neg_integer()]

  @doc """
  Stubs `Trogon.Test.MockRand` to draw from the real `:rand`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestRand, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockRand, __MODULE__.ErlangRand)
    :ok
  end

  @doc """
  Expects `uniform/1` on the mock, returning `opts[:returns]`.
  """
  @spec expect_uniform(expect_opts()) :: module()
  def expect_uniform(opts) do
    recorder = Recorder.new()
    value = Expectation.returns!(opts, &(is_integer(&1) and &1 >= 1), "a positive integer")

    Mox.expect(MockRand, :uniform, Expectation.times(opts), fn n when is_integer(n) and n >= 1 ->
      if value > n do
        raise ArgumentError, "expected :returns to be at most #{n}, the n uniform/1 was given, got: #{value}"
      end

      Expectation.record(recorder, __MODULE__, {:uniform, [n]}, value)
    end)
  end

  @doc """
  Asserts an expected `uniform/1` call was given `n`.
  """
  defmacro assert_received_uniform(n) do
    quote bind_quoted: [n: n] do
      Recorder.asserted(ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestRand, {:uniform, [^n]}}}))
    end
  end
end
