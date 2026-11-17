defmodule Trogon.Test.TestEnum.ElixirEnum do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Enum

  @impl true
  defdelegate random(enumerable), to: Enum
end
