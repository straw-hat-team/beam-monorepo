defmodule Trogon.Test.TestProcess.ElixirProcess do
  @moduledoc false
  @behaviour Trogon.Test.Behaviour.Process

  @impl true
  defdelegate send_after(dest, msg, time, opts), to: Process

  @impl true
  defdelegate sleep(timeout), to: Process
end
