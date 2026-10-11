defmodule Trogon.Test do
  @moduledoc """
  Assertions shared by every `Trogon.Test` mock.

  Every expected call a mock records lands in the test's mailbox under the
  `Trogon.Test` tag, whichever mock recorded it. Each `assert_received_*` macro
  takes one of them out, so a test that ends with `assert_empty_mailbox/0`
  proves it asserted on every call the code under test made:

      require Trogon.Test
      require Trogon.Test.TestApplication

      test "charges the configured tax rate" do
        Trogon.Test.TestApplication.expect_get_env(times: 1, returns: 0.07)

        tax_rate = MyApp.Billing.tax_rate()

        assert tax_rate == 0.07
        Trogon.Test.TestApplication.assert_received_get_env(:my_app, :tax_rate)
        Trogon.Test.assert_empty_mailbox()
      end
  """

  @mocks [Trogon.Test.MockApplication, Trogon.Test.MockDateTime]

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
