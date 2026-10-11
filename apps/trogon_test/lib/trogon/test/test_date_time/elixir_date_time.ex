defmodule Trogon.Test.TestDateTime.ElixirDateTime do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.DateTime

  @impl true
  defdelegate utc_now(), to: DateTime
end
