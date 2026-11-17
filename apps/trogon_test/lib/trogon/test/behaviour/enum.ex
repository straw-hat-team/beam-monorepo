defmodule Trogon.Test.Behaviour.Enum do
  @moduledoc """
  The `Enum` functions `Trogon.Test.MockEnum` mocks.
  """

  @callback random(enumerable :: Enumerable.t()) :: term()
end
