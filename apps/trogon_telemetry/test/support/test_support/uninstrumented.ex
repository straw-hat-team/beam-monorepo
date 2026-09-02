defmodule Trogon.Telemetry.TestSupport.Uninstrumented do
  @moduledoc "Declares nothing a reporter would aggregate."

  use Trogon.Telemetry.TestSupport.Catalog, :event

  event [:hooks, :uninstrumented] do
    measurements do
      field(:count, :integer)
    end

    attributes do
      field(:reason, :string)
    end
  end
end
