defmodule Trogon.Telemetry.DefinitionTest do
  use ExUnit.Case, async: true

  alias Trogon.Telemetry.Definition
  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery

  describe "emitted/1" do
    test "an event emits a single name" do
      assert Definition.emitted(LogStreamDelivery.__telemetry__()) == [
               {:event, [:trogon_telemetry_test, :hooks, :log_stream_delivery]}
             ]
    end

    test "a span emits the three names telemetry expects" do
      assert Definition.emitted(DeliverLogStream.__telemetry__()) == [
               {:start, [:trogon_telemetry_test, :hooks, :deliver_log_stream, :start]},
               {:stop, [:trogon_telemetry_test, :hooks, :deliver_log_stream, :stop]},
               {:exception, [:trogon_telemetry_test, :hooks, :deliver_log_stream, :exception]}
             ]
    end
  end

  describe "tags/1" do
    test "only the attributes marked as safe to break a metric down by" do
      assert Definition.tags(LogStreamDelivery.__telemetry__()) == [:project_id, :result]
    end
  end

  describe "fields_for/3" do
    test "narrows a span section to one phase" do
      definition = DeliverLogStream.__telemetry__()

      assert Enum.map(Definition.fields_for(definition, :measurements, :start), & &1.name) ==
               [:system_time, :monotonic_time]

      assert Enum.map(Definition.fields_for(definition, :attributes, :exception), & &1.name) ==
               [:project_id, :telemetry_span_context, :kind, :reason, :stacktrace]
    end
  end
end
