defmodule Trogon.Test.TestEnum do
  @moduledoc """
  Helpers for `Trogon.Test.MockEnum`, the Mox mock of `Enum.random/1`, that
  expect a pick and assert on what it was given.

  Code that calls `Enum.random/1` directly picks a different element on every
  run, so a test cannot pin the branch it takes, such as which replica it
  routes to. Pick through a facade the project compiles in, `Enum` in every
  environment but test:

      defmodule MyApp do
        @enum Application.compile_env(:my_app, [__MODULE__, :enum], Enum)

        defdelegate random(enumerable), to: @enum
      end

  and in `config/test.exs`:

      config :my_app, MyApp, enum: Trogon.Test.MockEnum

  The code under test keeps calling the rest of `Enum` directly, since only
  `random/1` draws.

  `use Trogon.Test` stubs the mock to pick with the real `Enum.random/1`. Each
  test expects the picks it cares about with what they return, and asserts on
  what they were given:

      use Trogon.Test

      test "routes to a replica" do
        TestEnum.expect_random(times: 1, returns: :replica_b)

        assert MyApp.Router.pick() == :replica_b

        TestEnum.assert_received_random([:replica_a, :replica_b])
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_random/1` takes:

    * `:returns` - the element every expected call returns. Required. A call
      given an enumerable that does not hold it raises `ArgumentError`, since
      `Enum.random/1` only returns one of its elements, and a call given an
      empty enumerable raises `Enum.EmptyError`, as `Enum.random/1` does.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_random/1`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockEnum
  alias Trogon.Test.Recorder

  @typedoc "Options `expect_random/1` takes."
  @type expect_opts :: [returns: term(), times: non_neg_integer()]

  @doc """
  Stubs `Trogon.Test.MockEnum` to pick with the real `Enum.random/1`.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestEnum, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockEnum, __MODULE__.ElixirEnum)
    :ok
  end

  @doc """
  Expects `random/1` on the mock, returning `opts[:returns]`.
  """
  @spec expect_random(expect_opts()) :: module()
  def expect_random(opts) do
    recorder = Recorder.new()
    value = Expectation.returns!(opts)

    Mox.expect(MockEnum, :random, Expectation.times(opts), fn enumerable ->
      case find(enumerable, value) do
        :found ->
          Expectation.record(recorder, __MODULE__, {:random, [enumerable]}, value)

        :empty ->
          raise Enum.EmptyError

        :missing ->
          raise ArgumentError,
                "expected :returns to be an element of the enumerable random/1 was given, " <>
                  "got: #{inspect(value)} for #{inspect(enumerable)}"
      end
    end)
  end

  # Walks the enumerable once, so a single-use one, such as an `IO.stream/2`,
  # is not exhausted before membership is checked.
  defp find(enumerable, value) do
    Enum.reduce_while(enumerable, :empty, fn
      ^value, _acc -> {:halt, :found}
      _element, _acc -> {:cont, :missing}
    end)
  end

  @doc """
  Asserts an expected `random/1` call was given `enumerable`.
  """
  defmacro assert_received_random(enumerable) do
    quote bind_quoted: [enumerable: enumerable] do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestEnum, {:random, [^enumerable]}}})
      )
    end
  end
end
