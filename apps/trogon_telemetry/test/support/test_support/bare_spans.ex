defmodule Trogon.Telemetry.TestSupport.BareSpans do
  @moduledoc false

  defmodule Refined do
    @moduledoc false
    use Trogon.Telemetry.Span

    span [:bare, :refined], duration: [unit: {:native, :microsecond}, buckets: [1, 10]] do
      measurements do
      end

      attributes do
      end
    end
  end

  defmodule Untimed do
    @moduledoc false
    use Trogon.Telemetry.Span

    span [:bare, :untimed], duration: false do
      measurements do
      end

      attributes do
      end
    end
  end
end
