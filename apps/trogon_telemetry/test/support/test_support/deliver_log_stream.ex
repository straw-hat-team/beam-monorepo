defmodule Trogon.Telemetry.TestSupport.DeliverLogStream do
  @moduledoc "Wraps a single delivery attempt."

  use Trogon.Telemetry.TestSupport.Catalog, :span

  alias Trogon.Telemetry.TestSupport.ProjectId

  span [:hooks, :deliver_log_stream] do
    measurements do
      field(:bytes_sent, :integer,
        metric: :histogram,
        unit: :byte,
        tags: [:project_id],
        doc: "Payload size handed to the destination."
      )
    end

    attributes do
      field(:project_id, ProjectId, tag: true)
      field(:result, {:enum, [:ok, :error]}, tag: true, phase: :stop)
    end
  end
end
