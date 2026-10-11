defmodule Trogon.Test.TestProcess.ElixirProcess do
  @moduledoc false
  @behaviour Trogon.Test.TestProcess

  @impl true
  defdelegate send_after(dest, msg, time, opts), to: Process
end
