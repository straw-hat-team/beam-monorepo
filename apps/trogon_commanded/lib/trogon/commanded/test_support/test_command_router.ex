if Code.ensure_loaded?(Mox) and Code.ensure_loaded?(Trogon.Test.Recorder) do
  defmodule Trogon.Commanded.TestSupport.TestCommandRouter do
    @expect_opts_schema NimbleOptions.new!(
                          times: [
                            type: :non_neg_integer,
                            default: 1,
                            doc: "How many dispatches the expectation covers."
                          ],
                          returns: [
                            type: {:custom, __MODULE__, :__validate_returns__, []},
                            default: :ok,
                            doc: """
                            What each dispatch returns. Any value `c:Commanded.Application.dispatch/2`
                            returns: `:ok`, `{:ok, aggregate_state}`,
                            `{:ok, %Commanded.Commands.ExecutionResult{}}` or `{:error, reason}`.
                            """
                          ]
                        )

    @moduledoc ~S"""
    Helpers for the Mox mock of `Commanded.Application` that expect a dispatch
    and assert on the command it was given. The mock is the module
    Trogon.Commanded.TestSupport.MockCommandedApplication.

    The modules exist only where the project has `:mox` and `:trogon_test`, so add
    both to the test environment:

        {:mox, "~> 1.2", only: :test},
        {:trogon_test, "~> 0.6", only: :test}

    Point the code that dispatches commands at the mock in `config/test.exs`. The
    key is whatever your project reads to pick its router:

        config :acme, Acme.Billing, command_router: Trogon.Commanded.TestSupport.MockCommandedApplication

    Each test expects the dispatch, runs the code under test, and asserts on the
    command:

        defmodule Acme.BillingTest do
          use ExUnit.Case, async: true
          use Trogon.Test

          require Trogon.Commanded.TestSupport.TestCommandRouter, as: TestCommandRouter

          test "charges the card" do
            TestCommandRouter.expect_dispatch()

            assert :ok = Acme.Billing.charge("card-1", 1_000)

            TestCommandRouter.assert_received_dispatch(%Acme.Billing.ChargeCard{card_id: "card-1", cents: 1_000}, [])
          end

          test "reports a declined card" do
            TestCommandRouter.expect_dispatch(returns: {:error, :card_declined})

            assert {:error, :card_declined} = Acme.Billing.charge("card-1", 1_000)

            TestCommandRouter.assert_received_dispatch(%Acme.Billing.ChargeCard{card_id: "card-1", cents: 1_000}, [])
          end
        end

    ## Options

    `expect_dispatch/1` takes:

    #{NimbleOptions.docs(@expect_opts_schema)}

    A dispatch past `:times` raises `Mox.UnexpectedCallError`, and a dispatch
    that never happens fails the test through `Mox.verify_on_exit!/1`, which
    `use Trogon.Test` runs. Each expected dispatch is recorded in the mailbox of
    the test that set it, for `assert_received_dispatch/2`, and
    `use Trogon.Test` fails the test on a dispatch no assertion covers, through
    `Trogon.Test.verify_mailbox_on_exit!/1`. The expectation reaches the test's `$callers`, such as a `Task`, and
    a process allowed with `Trogon.Test.allow/1`.

    ## Dispatch arity

    Only `dispatch/2` is covered, and it records its second argument, the timeout
    or the options, as the options of the call. Mox keeps one expectation per
    function and arity, so also expecting `dispatch/1` would leave whichever of
    the two the code under test does not call unmet. Call `dispatch/2`, passing
    `[]` when there are no options.
    """

    alias Commanded.Commands.ExecutionResult
    alias Trogon.Commanded.TestSupport.MockCommandedApplication
    alias Trogon.Test.Recorder

    @typedoc "Options `expect_dispatch/1` takes."
    @type expect_opts :: [returns: Commanded.Commands.Router.dispatch_resp(), times: non_neg_integer()]

    @doc """
    Expects `dispatch/2` on the mock, returning `opts[:returns]`.

    Raises `NimbleOptions.ValidationError` when `:times` is not a non-negative
    integer, when `:returns` is not a value `c:Commanded.Application.dispatch/2`
    returns, or on an unknown option.
    """
    @spec expect_dispatch(expect_opts()) :: module()
    def expect_dispatch(opts \\ []) do
      opts = validate_opts!(opts)
      recorder = Recorder.new()

      Mox.expect(MockCommandedApplication, :dispatch, opts[:times], fn command, dispatch_opts ->
        Recorder.record(recorder, {Trogon.Test, {__MODULE__, {:dispatch, [command, dispatch_opts]}}})
        opts[:returns]
      end)
    end

    defp validate_opts!(opts), do: NimbleOptions.validate!(opts, @expect_opts_schema)

    @doc false
    def __validate_returns__(:ok), do: {:ok, :ok}
    def __validate_returns__({:ok, _aggregate_state_or_result} = returns), do: {:ok, returns}
    def __validate_returns__({:error, _reason} = returns), do: {:ok, returns}

    def __validate_returns__(returns) do
      {:error,
       "expected :returns to be :ok, {:ok, aggregate_state}, {:ok, %#{inspect(ExecutionResult)}{}} " <>
         "or {:error, reason}, got: #{inspect(returns)}"}
    end

    @doc """
    Asserts an expected `dispatch/2` call dispatched `command` with `opts`.

    Both are matched by value, as the pinned arguments of
    `ExUnit.Assertions.assert_received/1`, so pass the whole command and the
    exact options or timeout the code under test dispatched with:

        TestCommandRouter.assert_received_dispatch(%Acme.Billing.ChargeCard{card_id: "card-1", cents: 1_000}, [])
        TestCommandRouter.assert_received_dispatch(command, timeout: 5_000)
    """
    defmacro assert_received_dispatch(command, opts) do
      quote bind_quoted: [command: command, opts: opts] do
        Recorder.asserted(
          ExUnit.Assertions.assert_received(
            {Trogon.Test, {Trogon.Commanded.TestSupport.TestCommandRouter, {:dispatch, [^command, ^opts]}}}
          )
        )
      end
    end
  end
end
