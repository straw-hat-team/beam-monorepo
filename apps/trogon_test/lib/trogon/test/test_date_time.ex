defmodule Trogon.Test.TestDateTime do
  @moduledoc """
  A Mox behaviour for reading the current time, with
  `Trogon.Test.MockDateTime` as its mock and helpers that expect a read and
  assert it happened.

  Code that calls `DateTime.utc_now/0` directly returns a different value on
  every run, so a test can only assert on its shape. Read the clock through a
  facade the project compiles in, `DateTime` in every environment but test:

      defmodule MyApp.Clock do
        @date_time Application.compile_env(:my_app, [__MODULE__, :date_time], DateTime)

        defdelegate utc_now(), to: @date_time
      end

  and in `config/test.exs`:

      config :my_app, MyApp.Clock, date_time: Trogon.Test.MockDateTime

  `use Trogon.Test` stubs the mock to read the real clock. Each test expects the
  reads it cares about with what they return, and asserts they happened:

      use Trogon.Test

      test "stamps the invoice with the current time" do
        TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

        invoice = MyApp.Billing.issue_invoice()

        assert invoice.issued_at == ~U[2026-01-01 00:00:00Z]
        TestDateTime.assert_received_utc_now()
        Trogon.Test.assert_empty_mailbox()
      end

  `expect_utc_now/1` takes:

    * `:returns` - the `DateTime` the expected call returns. Required.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_utc_now/0`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Trogon.Test.allow/1`.
  """

  alias Trogon.Test.Expectation
  alias Trogon.Test.MockDateTime

  @typedoc "Options `expect_utc_now/1` takes."
  @type expect_opts :: [returns: DateTime.t(), times: non_neg_integer()]

  @callback utc_now() :: DateTime.t()

  @doc """
  Stubs `Trogon.Test.MockDateTime` to read the real clock.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.TestDateTime, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(MockDateTime, __MODULE__.ElixirDateTime)
    :ok
  end

  @doc """
  Expects `utc_now/0` on the mock, returning `opts[:returns]`.
  """
  @spec expect_utc_now(expect_opts()) :: module()
  def expect_utc_now(opts) do
    owner = self()
    datetime = Expectation.returns!(opts, &utc_date_time?/1, "a DateTime in Etc/UTC")

    Mox.expect(MockDateTime, :utc_now, Expectation.times(opts), fn ->
      Expectation.record(owner, __MODULE__, {:utc_now, []}, datetime)
    end)
  end

  @doc """
  Asserts an expected `utc_now/0` call was made.
  """
  defmacro assert_received_utc_now do
    quote do
      ExUnit.Assertions.assert_received({Trogon.Test, {Trogon.Test.TestDateTime, {:utc_now, []}}})
    end
  end

  defp utc_date_time?(%DateTime{time_zone: "Etc/UTC"}), do: true
  defp utc_date_time?(_value), do: false
end
