defmodule OnePiece.GracefulShutdown.State do
  @moduledoc false

  defstruct init_stop?: true, shutdown_delay_ms: 10_000, notify_pid: nil

  def new(opts) do
    Map.merge(%__MODULE__{}, Enum.into(opts, %{}))
  end
end
