defmodule Trogon.Test.Behaviour.Task do
  @moduledoc """
  The `Task` functions `Trogon.Test.MockTask` mocks.
  """

  @callback async(fun :: (-> term())) :: Task.t()
  @callback await(task :: Task.t(), timeout :: timeout()) :: term()
  @callback async_stream(enumerable :: Enumerable.t(), fun :: (term() -> term()), opts :: keyword()) :: Enumerable.t()
end
