defmodule Trogon.Test.TestProcess.ProcessBehaviour do
  @moduledoc false

  @callback send_after(dest :: pid() | atom(), msg :: term(), time :: non_neg_integer(), opts :: keyword()) ::
              reference()
  @callback sleep(timeout :: timeout()) :: :ok
end
