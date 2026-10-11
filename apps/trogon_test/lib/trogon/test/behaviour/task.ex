defmodule Trogon.Test.Behaviour.Task do
  @moduledoc """
  The `Task` functions `Trogon.Test.MockTask` mocks.
  """

  @callback async(fun :: (-> term())) :: Task.t()
end
