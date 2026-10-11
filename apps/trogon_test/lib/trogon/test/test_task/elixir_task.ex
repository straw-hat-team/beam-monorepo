defmodule Trogon.Test.TestTask.ElixirTask do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Task

  @impl true
  defdelegate async(fun), to: Task

  @impl true
  defdelegate await(task, timeout), to: Task

  @impl true
  defdelegate async_stream(enumerable, fun, opts), to: Task
end
