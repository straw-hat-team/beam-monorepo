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
