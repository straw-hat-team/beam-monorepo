defmodule Trogon.Test.TestRand.ErlangRand do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Rand

  @impl true
  defdelegate uniform(n), to: :rand
end
