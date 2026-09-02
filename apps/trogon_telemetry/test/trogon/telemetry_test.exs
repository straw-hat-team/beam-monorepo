defmodule Trogon.TelemetryTest do
  use ExUnit.Case, async: true

  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery
  alias Trogon.Telemetry.TestSupport.ProjectId

  @delivery [:trogon_telemetry_test, :hooks, :log_stream_delivery]
  @span [:trogon_telemetry_test, :hooks, :deliver_log_stream]

  describe "execute/1" do
    test "emits the declared name with the measurements and the attributes as built" do
      ref = :telemetry_test.attach_event_handlers(self(), [@delivery])
      project_id = %ProjectId{value: "prj_1"}

      assert :ok =
               Trogon.Telemetry.execute(%LogStreamDelivery{
                 attributes: %LogStreamDelivery.Attributes{
                   project_id: project_id,
                   log_stream_id: "ls_1",
                   result: :ok
                 }
               })

      assert_receive {@delivery, ^ref, measurements, attributes}
      assert measurements == %LogStreamDelivery.Measurements{count: 1}
      assert attributes == %LogStreamDelivery.Attributes{project_id: project_id, log_stream_id: "ls_1", result: :ok}
    end

    test "carries declared measurements when they are set" do
      ref = :telemetry_test.attach_event_handlers(self(), [@delivery])

      Trogon.Telemetry.execute(%LogStreamDelivery{
        measurements: %LogStreamDelivery.Measurements{count: 37}
      })

      assert_receive {@delivery, ^ref, %LogStreamDelivery.Measurements{count: 37}, _attributes}
    end

    test "refuses a span" do
      assert_raise ArgumentError, ~r/is a span, use Trogon.Telemetry.span\/2/, fn ->
        Trogon.Telemetry.execute(%DeliverLogStream{})
      end
    end
  end

  describe "span/2" do
    setup do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          @span ++ [:start],
          @span ++ [:stop],
          @span ++ [:exception]
        ])

      project_id = %ProjectId{value: "prj_1"}

      %{
        ref: ref,
        event: %DeliverLogStream{attributes: %DeliverLogStream.Attributes{project_id: project_id}}
      }
    end

    test "emits start and stop around the function", %{ref: ref, event: event} do
      assert :delivered =
               Trogon.Telemetry.span(event, fn ->
                 stopped = %{
                   event
                   | measurements: %DeliverLogStream.Measurements{bytes_sent: 42},
                     attributes: %{event.attributes | result: :ok}
                 }

                 {:delivered, stopped}
               end)

      start = @span ++ [:start]
      stop = @span ++ [:stop]

      assert_receive {^start, ^ref, start_measurements, start_attributes}
      assert %DeliverLogStream.Start.Measurements{} = start_measurements
      assert is_integer(start_measurements.system_time)
      assert is_integer(start_measurements.monotonic_time)
      assert %DeliverLogStream.Start.Attributes{} = start_attributes
      assert is_reference(start_attributes.telemetry_span_context)

      assert_receive {^stop, ^ref, stop_measurements, stop_attributes}
      assert %DeliverLogStream.Stop.Measurements{bytes_sent: 42} = stop_measurements
      assert is_integer(stop_measurements.duration)
      assert %DeliverLogStream.Stop.Attributes{result: :ok} = stop_attributes
      assert stop_attributes.project_id == event.attributes.project_id
      assert stop_attributes.telemetry_span_context == start_attributes.telemetry_span_context
    end

    test "carries only what the phase declares", %{ref: ref, event: event} do
      Trogon.Telemetry.span(event, fn -> {:ok, event} end)

      start = @span ++ [:start]
      stop = @span ++ [:stop]

      assert_receive {^start, ^ref, start_measurements, start_attributes}
      assert fields(start_measurements) == [:monotonic_time, :system_time]
      assert fields(start_attributes) == [:project_id, :telemetry_span_context]

      assert_receive {^stop, ^ref, stop_measurements, stop_attributes}
      assert fields(stop_measurements) == [:bytes_sent, :duration, :monotonic_time]
      assert fields(stop_attributes) == [:project_id, :result, :telemetry_span_context]
    end

    test "emits exception with the start attributes and re-raises", %{ref: ref, event: event} do
      assert_raise RuntimeError, "boom", fn ->
        Trogon.Telemetry.span(event, fn -> raise "boom" end)
      end

      exception = @span ++ [:exception]

      assert_receive {^exception, ^ref, measurements, attributes}
      assert %DeliverLogStream.Exception.Measurements{} = measurements
      assert is_integer(measurements.duration)
      assert %DeliverLogStream.Exception.Attributes{kind: :error, reason: %RuntimeError{message: "boom"}} = attributes
      assert is_list(attributes.stacktrace)
      assert attributes.project_id == event.attributes.project_id
      refute Map.has_key?(attributes, :result)
    end

    test "reuses a span context that is already set", %{ref: ref, event: event} do
      context = make_ref()
      event = %{event | attributes: %{event.attributes | telemetry_span_context: context}}

      Trogon.Telemetry.span(event, fn -> {:ok, event} end)

      start = @span ++ [:start]
      assert_receive {^start, ^ref, _measurements, %{telemetry_span_context: ^context}}
    end

    test "refuses an event" do
      event = opaque(%LogStreamDelivery{})

      assert_raise ArgumentError, ~r/is an event, use Trogon.Telemetry.execute\/1/, fn ->
        Trogon.Telemetry.span(event, fn -> {:ok, event} end)
      end
    end

    test "rejects a function that does not return the event", %{event: event} do
      assert_raise ArgumentError, ~r/expected the span function to return/, fn ->
        Trogon.Telemetry.span(event, fn -> :oops end)
      end
    end
  end

  @spec opaque(struct()) :: struct()
  defp opaque(event), do: event

  defp fields(struct), do: struct |> Map.from_struct() |> Map.keys() |> Enum.sort()
end
