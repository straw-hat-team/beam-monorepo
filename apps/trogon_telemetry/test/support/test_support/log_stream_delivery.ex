defmodule Trogon.Telemetry.TestSupport.LogStreamDelivery do
  @moduledoc "Emitted once per delivery attempt to a log stream destination."

  use Trogon.Telemetry.TestSupport.Catalog, :event

  alias Trogon.Telemetry.TestSupport.ProjectId

  event [:hooks, :log_stream_delivery] do
    measurements do
      field(:count, :integer,
        default: 1,
        metric: :counter,
        unit: :delivery,
        doc: "Always 1. Sum it for delivery volume."
      )
    end

    attributes do
      field(:project_id, ProjectId, tag: true, doc: "Owning project.")
      field(:log_stream_id, :string)
      field(:result, {:enum, [:ok, :error]}, tag: true)
    end
  end
end
