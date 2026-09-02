defmodule Trogon.Telemetry.MetricsTest do
  use ExUnit.Case, async: true

  alias Telemetry.Metrics.Distribution
  alias Telemetry.Metrics.LastValue
  alias Telemetry.Metrics.Sum
  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.Metrics
  alias Trogon.Telemetry.TestSupport.BareSpans
  alias Trogon.Telemetry.TestSupport.Catalog
  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.EctoQuery
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery
  alias Trogon.Telemetry.TestSupport.ProjectId
  alias Trogon.Telemetry.TestSupport.Uninstrumented

  describe "aggregation" do
    test "a counter becomes a sum" do
      assert [%Sum{} = metric] = Metrics.for_definition(LogStreamDelivery.__telemetry__())

      assert metric.name == [:trogon_telemetry_test, :hooks, :log_stream_delivery, :count]
      assert metric.event_name == [:trogon_telemetry_test, :hooks, :log_stream_delivery]
      assert metric.description == "Always 1. Sum it for delivery volume."
      assert metric.unit == :delivery
      assert metric.tags == [:project_id, :result]
    end

    test "a histogram becomes a distribution and a gauge becomes a last value" do
      assert [%Distribution{}, %LastValue{}] = Metrics.for_definition(EctoQuery.__telemetry__())
    end

    test "a measurement without an instrument derives nothing" do
      assert Metrics.for_definition(Uninstrumented.__telemetry__()) == []
    end
  end

  describe "reading a measurement" do
    test "reads the struct that a reporter would fail to index into" do
      [metric] = Metrics.for_definition(LogStreamDelivery.__telemetry__())
      measurements = %LogStreamDelivery.Measurements{count: 7}

      assert_raise UndefinedFunctionError, fn -> measurements[:count] end
      assert metric.measurement.(measurements) == 7
    end

    test "converts into the reported unit" do
      [total_time, _idle_time] = Metrics.for_definition(EctoQuery.__telemetry__())
      ratio = 1 / System.convert_time_unit(1, :millisecond, :native)

      assert total_time.unit == :millisecond
      assert total_time.measurement.(%{total_time: 2_000_000}) == 2_000_000 * ratio
    end
  end

  describe "reading tags" do
    test "dumps a value object into a scalar" do
      [metric] = Metrics.for_definition(LogStreamDelivery.__telemetry__())

      attributes = %LogStreamDelivery.Attributes{
        project_id: %ProjectId{value: "proj_123"},
        log_stream_id: "stream_1",
        result: :ok
      }

      assert metric.tag_values.(attributes) == %{project_id: "proj_123", result: :ok}
    end

    test "leaves untagged attributes out entirely" do
      [metric] = Metrics.for_definition(LogStreamDelivery.__telemetry__())

      refute Map.has_key?(metric.tag_values.(%LogStreamDelivery.Attributes{}), :log_stream_id)
    end

    test "narrows the breakdown when the measurement declares its own tags" do
      metrics = Metrics.for_definition(DeliverLogStream.__telemetry__())
      bytes_sent = Enum.find(metrics, &List.ends_with?(&1.name, [:bytes_sent]))

      assert bytes_sent.tags == [:project_id]
    end
  end

  describe "spans" do
    test "derive a duration metric for every phase carrying it" do
      names =
        DeliverLogStream.__telemetry__()
        |> Metrics.for_definition()
        |> Enum.map(& &1.name)

      assert names == [
               [:trogon_telemetry_test, :hooks, :deliver_log_stream, :stop, :bytes_sent],
               [:trogon_telemetry_test, :hooks, :deliver_log_stream, :stop, :duration],
               [:trogon_telemetry_test, :hooks, :deliver_log_stream, :exception, :duration]
             ]
    end

    test "only tag the phase that carries the attribute" do
      [_bytes_sent, stop_duration, exception_duration] =
        Metrics.for_definition(DeliverLogStream.__telemetry__())

      assert stop_duration.tags == [:project_id, :result]
      assert exception_duration.tags == [:project_id]
    end

    test "duration can be refined" do
      [stop, exception] = Metrics.for_definition(BareSpans.Refined.__telemetry__())

      assert stop.unit == :microsecond
      assert exception.unit == :microsecond
      assert %{buckets: [1, 10]} = duration_instrument(BareSpans.Refined)
    end

    test "duration can be turned off" do
      assert Metrics.for_definition(BareSpans.Untimed.__telemetry__()) == []
      assert duration_instrument(BareSpans.Untimed) == nil
    end
  end

  describe "for_catalog/1" do
    test "collects every metric declared under the catalog" do
      names = Enum.map(Metrics.for_catalog(Catalog), & &1.name)

      assert [:some_other_app, :repo, :query, :total_time] in names
      assert [:trogon_telemetry_test, :hooks, :log_stream_delivery, :count] in names
      assert length(names) == length(Enum.uniq(names))
    end

    test "the catalog exposes it directly" do
      assert Catalog.metrics() == Metrics.for_catalog(Catalog)
    end
  end

  describe "against what actually reaches the wire" do
    test "the derived metric reads the emitted event" do
      [metric] = Metrics.for_definition(LogStreamDelivery.__telemetry__())
      handler = :telemetry_test.attach_event_handlers(self(), [metric.event_name])

      on_exit(fn -> :telemetry.detach(handler) end)

      Trogon.Telemetry.execute(%LogStreamDelivery{
        measurements: %LogStreamDelivery.Measurements{count: 3},
        attributes: %LogStreamDelivery.Attributes{
          project_id: %ProjectId{value: "proj_123"},
          result: :error
        }
      })

      assert_receive {_name, ^handler, measurements, metadata}

      assert metric.measurement.(measurements) == 3

      assert metadata |> metric.tag_values.() |> Map.take(metric.tags) == %{
               project_id: "proj_123",
               result: :error
             }
    end
  end

  defp duration_instrument(module) do
    module.__telemetry__()
    |> Definition.fields_for(:measurements, :stop)
    |> Enum.find(&(&1.name == :duration))
    |> Map.fetch!(:instrument)
  end
end
