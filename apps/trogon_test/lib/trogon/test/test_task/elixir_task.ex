defmodule Trogon.Test.TestTask.ElixirTask do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Task

  @impl true
  defdelegate async(fun), to: Task
end
