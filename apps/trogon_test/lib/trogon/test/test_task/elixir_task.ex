defmodule Trogon.Test.TestTask.ElixirTask do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Task

  alias Trogon.Test.MockTask

  # The default arities call the mock with the defaults `Task` uses, so an
  # expectation on `await/2` or `async_stream/3` covers the shorter call too.
  @impl true
  defdelegate async(fun), to: Task

  @impl true
  def await(task), do: MockTask.await(task, 5000)

  @impl true
  defdelegate await(task, timeout), to: Task

  @impl true
  def async_stream(enumerable, fun), do: MockTask.async_stream(enumerable, fun, [])

  @impl true
  defdelegate async_stream(enumerable, fun, opts), to: Task
end
