defmodule Trogon.Test.Behaviour.Rand do
  @moduledoc """
  The `:rand` functions `Trogon.Test.MockRand` mocks.
  """

  @callback uniform(n :: pos_integer()) :: pos_integer()
end
