defmodule Trogon.Telemetry.TestSupport do
  @moduledoc false

  defmodule ProjectId do
    @moduledoc false
    @behaviour Trogon.Telemetry.Type

    @enforce_keys [:value]
    defstruct [:value]

    @impl true
    def dump(%__MODULE__{value: value}), do: value
  end

  defmodule Catalog do
    @moduledoc false
    use Trogon.Telemetry.Catalog,
      otp_app: :trogon_telemetry,
      prefix: [:trogon_telemetry_test]
  end
end
