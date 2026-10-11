if Code.ensure_loaded?(Uniq.UUID) do
  defmodule Trogon.Test.Behaviour.UUID do
    @moduledoc """
    The `Uniq.UUID` functions `Trogon.Test.MockUUID` mocks.
    """

    @callback uuid4(format :: Uniq.UUID.format()) :: Uniq.UUID.formatted()
    @callback uuid7(format :: Uniq.UUID.format()) :: Uniq.UUID.formatted()
  end
end
