if Code.ensure_loaded?(Uniq.UUID) do
  defmodule Trogon.Test.TestUUID.UniqUUID do
    @moduledoc false
    @behaviour Trogon.Test.Behaviour.UUID

    @impl true
    defdelegate uuid4(format), to: Uniq.UUID

    @impl true
    defdelegate uuid7(format), to: Uniq.UUID
  end
end
