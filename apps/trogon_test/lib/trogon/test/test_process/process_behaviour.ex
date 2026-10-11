defmodule Trogon.Test.TestProcess.ProcessBehaviour do
  @moduledoc """
  The `Process` functions `Trogon.Test.MockProcess` mocks.
  """

  @callback send_after(dest :: pid() | atom(), msg :: term(), time :: non_neg_integer(), opts :: keyword()) ::
              reference()
  @callback sleep(timeout :: timeout()) :: :ok
end
