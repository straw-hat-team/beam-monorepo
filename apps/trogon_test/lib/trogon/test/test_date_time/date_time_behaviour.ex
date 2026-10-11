defmodule Trogon.Test.TestDateTime.DateTimeBehaviour do
  @moduledoc """
  The `DateTime` functions `Trogon.Test.MockDateTime` mocks.
  """

  @callback utc_now() :: DateTime.t()
end
