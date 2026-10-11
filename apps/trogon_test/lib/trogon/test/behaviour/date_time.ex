defmodule Trogon.Test.Behaviour.DateTime do
  @moduledoc """
  The `DateTime` functions `Trogon.Test.MockDateTime` mocks.
  """

  @callback utc_now() :: DateTime.t()
end
