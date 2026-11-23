if Code.ensure_loaded?(Uniq.UUID) do
  defmodule Trogon.Test.TestUUID.UniqUUID do
    @moduledoc false
    @behaviour Trogon.Test.Behaviour.UUID

    alias Trogon.Test.MockUUID

    # The default arities call the mock with the default format, as
    # `Uniq.UUID` does, so an expectation on `/1` covers a `/0` call too.
    # Uniq exposes no constant for it; a test pins it to Uniq's signatures.
    @impl true
    def uuid4, do: MockUUID.uuid4(:default)

    @impl true
    defdelegate uuid4(format), to: Uniq.UUID

    @impl true
    def uuid7, do: MockUUID.uuid7(:default)

    @impl true
    defdelegate uuid7(format), to: Uniq.UUID
  end
end
