defmodule Trogon.Telemetry.TestSupport.DeliveryRecorder do
  @moduledoc false

  use Trogon.Telemetry.Handler,
    events: [
      Trogon.Telemetry.TestSupport.LogStreamDelivery,
      Trogon.Telemetry.TestSupport.DeliverLogStream
    ]

  @impl true
  def handle(event, phase, %{pid: pid}) do
    send(pid, {:handled, event, phase})
  end
end
