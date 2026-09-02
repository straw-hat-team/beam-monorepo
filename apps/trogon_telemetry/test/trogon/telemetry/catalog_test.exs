defmodule Trogon.Telemetry.CatalogTest do
  use ExUnit.Case, async: true

  alias Trogon.Telemetry.TestSupport.Catalog
  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.EctoQuery
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery
  alias Trogon.Telemetry.TestSupport.Uninstrumented

  test "owns the prefix every event is declared under" do
    assert Catalog.prefix() == [:trogon_telemetry_test]
    assert Catalog.otp_app() == :trogon_telemetry
    assert DeliverLogStream.__telemetry__().name == [:trogon_telemetry_test, :hooks, :deliver_log_stream]
  end

  test "collects every declaration of its application, sorted by name" do
    assert [
             %{module: EctoQuery, kind: :observation},
             %{module: DeliverLogStream},
             %{module: LogStreamDelivery},
             %{module: Uninstrumented}
           ] = Catalog.definitions()
  end

  test "rejects being used as anything other than a declaration kind" do
    assert_raise ArgumentError, ~r/can only be used as :event, :span or :observation/, fn ->
      Trogon.Telemetry.Catalog.__define__(Catalog, :handler)
    end
  end
end
