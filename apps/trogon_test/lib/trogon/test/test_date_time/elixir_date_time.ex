defmodule Trogon.Test.TestDateTime.ElixirDateTime do
  @moduledoc false
  @behaviour Trogon.Test.TestDateTime.DateTimeBehaviour

  @impl true
  defdelegate utc_now(), to: DateTime
end
