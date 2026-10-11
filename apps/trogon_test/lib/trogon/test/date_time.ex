defmodule Trogon.Test.DateTime do
  @moduledoc """
  A Mox behaviour for reading the current time, with
  `Trogon.Test.DateTime.Mock` as its mock and helpers that expect a read and
  assert it happened.

  Code that calls `DateTime.utc_now/0` directly returns a different value on
  every run, so a test can only assert on its shape. Read the clock through a
  facade the project compiles in, `DateTime` in every environment but test:

      defmodule MyApp.Clock do
        @date_time Application.compile_env(:my_app, [MyApp, :date_time], DateTime)

        defdelegate utc_now(), to: @date_time
      end

  and in `config/test.exs`:

      config :my_app, MyApp, date_time: Trogon.Test.DateTime.Mock

  Each test stubs the mock to read the real clock, expects the reads it cares
  about with what they return, and asserts they happened:

      import Mox

      require Trogon.Test.DateTime

      setup :verify_on_exit!
      setup {Trogon.Test.DateTime, :stub}

      test "stamps the invoice with the current time" do
        Trogon.Test.DateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

        invoice = MyApp.Billing.issue_invoice()

        assert invoice.issued_at == ~U[2026-01-01 00:00:00Z]
        Trogon.Test.DateTime.assert_received_utc_now()
      end

  `expect_utc_now/1` takes:

    * `:returns` - the `DateTime` the expected call returns. Required.
    * `:times` - how many calls the expectation covers. Defaults to `1`.

  A call past `:times` raises `Mox.UnexpectedCallError`. Each expected call is
  recorded in the mailbox of the test that set it, for
  `assert_received_utc_now/0`, a macro that needs
  `require Trogon.Test.DateTime`.

  The expectations reach the test's `$callers`, such as a `Task`, and a process
  allowed with `Mox.allow(Trogon.Test.DateTime.Mock, self(), pid)`.

  > #### Do not alias this module without `as:` {: .warning}
  >
  > `alias Trogon.Test.DateTime` shadows the real `DateTime` module for the
  > rest of that file. Give it another name instead:
  >
  >     alias Trogon.Test.DateTime, as: TestDateTime
  """

  alias Trogon.Test.Expectation

  @typedoc "Options `expect_utc_now/1` takes."
  @type expect_opts :: [returns: DateTime.t(), times: non_neg_integer()]

  @callback utc_now() :: DateTime.t()

  @doc """
  Stubs `Trogon.Test.DateTime.Mock` to read the real clock.

  Takes the test context so it can be given to `setup/1` as
  `setup {Trogon.Test.DateTime, :stub}`.
  """
  @spec stub(map()) :: :ok
  def stub(_context \\ %{}) do
    Mox.stub_with(__MODULE__.Mock, __MODULE__.ElixirDateTime)
    :ok
  end

  @doc """
  Expects `utc_now/0` on the mock, returning `opts[:returns]`.
  """
  @spec expect_utc_now(expect_opts()) :: module()
  def expect_utc_now(opts) do
    owner = self()
    %DateTime{} = datetime = Expectation.returns!(opts)

    Mox.expect(__MODULE__.Mock, :utc_now, Expectation.times(opts), fn ->
      Expectation.record(owner, __MODULE__, {:utc_now, []}, datetime)
    end)
  end

  @doc """
  Asserts an expected `utc_now/0` call was made.
  """
  defmacro assert_received_utc_now do
    quote do
      ExUnit.Assertions.assert_received({Trogon.Test.DateTime, {:utc_now, []}})
    end
  end
end

defmodule Trogon.Test.DateTime.ElixirDateTime do
  @moduledoc false
  @behaviour Trogon.Test.DateTime

  @impl true
  defdelegate utc_now(), to: DateTime
end

Mox.defmock(Trogon.Test.DateTime.Mock,
  for: Trogon.Test.DateTime,
  moduledoc: """
  The Mox mock for `Trogon.Test.DateTime`.

  Stub it with `Trogon.Test.DateTime.stub/1`, then expect reads with
  `Trogon.Test.DateTime.expect_utc_now/1`.
  """
)
