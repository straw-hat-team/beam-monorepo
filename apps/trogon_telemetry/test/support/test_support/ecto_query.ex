defmodule Trogon.Telemetry.TestSupport.EctoQuery do
  @moduledoc "Every query the repo runs."

  use Trogon.Telemetry.TestSupport.Catalog, :observation

  observe [:some_other_app, :repo, :query] do
    measurements do
      field(:total_time, :integer,
        metric: :histogram,
        unit: {:native, :millisecond},
        buckets: [10, 50, 100],
        doc: "Queue, query and decode time together."
      )

      field(:idle_time, :integer, metric: :gauge, unit: {:native, :millisecond})
    end

    attributes do
      field(:source, :string, tag: true)
    end
  end
end
