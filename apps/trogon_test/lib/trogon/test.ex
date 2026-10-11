defmodule Trogon.Test do
  @moduledoc """
  Sets a test module up to use every `Trogon.Test` mock, and holds the
  assertions they share.

  `use Trogon.Test` next to any case template, your own `DataCase` included, or
  once inside that template's `using` block:

      defmodule MyApp.BillingTest do
        use ExUnit.Case, async: true
        use Trogon.Test

        test "charges the configured tax rate" do
          TestApplication.expect_get_env(times: 1, returns: 0.07)

          tax_rate = MyApp.Billing.tax_rate()

          assert tax_rate == 0.07
          TestApplication.assert_received_get_env(:my_app, :tax_rate)
          Trogon.Test.assert_empty_mailbox()
        end
      end

  It aliases and requires `Trogon.Test.TestApplication`,
  `Trogon.Test.TestDateTime`, and `Trogon.Test.TestProcess`, requires
  `Trogon.Test`, verifies every Mox expectation when the test exits, and stubs
  each mock to call the real module until the test expects a call.

  Every expected call a mock records lands in the test's mailbox under the
  `Trogon.Test` tag, whichever mock recorded it. Each `assert_received_*` macro
  takes one of them out, so a test that ends with `assert_empty_mailbox/0`
  proves it asserted on every call the code under test made.

  An expected call rejects the arguments the real function rejects, raising
  the same exception, and each `expect_*` function rejects a `:returns` the real
  function never returns, so a test cannot pass on a call that would fail in
  production.
  """

  defmacro __using__(_opts) do
    quote do
      alias Trogon.Test.TestApplication
      alias Trogon.Test.TestDateTime
      alias Trogon.Test.TestProcess

      require Trogon.Test
      require Trogon.Test.TestApplication
      require Trogon.Test.TestDateTime
      require Trogon.Test.TestProcess

      setup {Mox, :verify_on_exit!}
      setup {Trogon.Test.TestApplication, :stub}
      setup {Trogon.Test.TestDateTime, :stub}
      setup {Trogon.Test.TestProcess, :stub}
    end
  end

  @mocks [Trogon.Test.MockApplication, Trogon.Test.MockDateTime, Trogon.Test.MockProcess]

  @typedoc """
  A process to allow: its pid, or the name it registers under.
  """
  @type process :: pid() | atom() | {:global, term()} | {:via, module(), term()}

  @doc """
  Allows a process to use the expectations and stubs the calling test set on
  every `Trogon.Test` mock.

  The test's `$callers`, such as a `Task`, need no allowance. A process started
  another way, such as a `GenServer` under a supervisor, does. A name is looked
  up each time the process calls a mock, so a test can allow a process before
  it starts:

      Trogon.Test.allow(MyApp.Worker)
      start_supervised!(MyApp.Worker)
  """
  @spec allow(process()) :: :ok
  def allow(process) do
    owner = self()
    Enum.each(@mocks, &Mox.allow(&1, owner, fn -> GenServer.whereis(process) end))
  end

  @doc """
  Asserts that the test asserted on every call a `Trogon.Test` mock recorded.

  Messages that no `Trogon.Test` mock sent are left alone.
  """
  defmacro assert_empty_mailbox do
    quote do
      ExUnit.Assertions.refute_received({Trogon.Test, _})
    end
  end
end
