defmodule Trogon.Telemetry.HandlerTest do
  use ExUnit.Case, async: false

  alias Trogon.Telemetry.TestSupport.DeliverLogStream
  alias Trogon.Telemetry.TestSupport.DeliveryRecorder
  alias Trogon.Telemetry.TestSupport.LogStreamDelivery
  alias Trogon.Telemetry.TestSupport.ProjectId

  setup do
    :ok = DeliveryRecorder.attach(%{pid: self()})
    on_exit(&DeliveryRecorder.detach/0)
    %{project_id: %ProjectId{value: "prj_1"}}
  end

  test "rebuilds the envelope for an event", %{project_id: project_id} do
    Trogon.Telemetry.execute(%LogStreamDelivery{
      attributes: %LogStreamDelivery.Attributes{project_id: project_id, result: :error}
    })

    assert_receive {:handled, %LogStreamDelivery{} = event, :event}
    assert event.measurements == %LogStreamDelivery.Measurements{count: 1}
    assert event.attributes == %LogStreamDelivery.Attributes{project_id: project_id, result: :error}
  end

  test "rebuilds one envelope per span phase", %{project_id: project_id} do
    event = %DeliverLogStream{attributes: %DeliverLogStream.Attributes{project_id: project_id}}

    Trogon.Telemetry.span(event, fn ->
      {:ok, %{event | attributes: %{event.attributes | result: :ok}}}
    end)

    assert_receive {:handled, %DeliverLogStream.Start{} = started, :start}
    assert started.attributes.project_id == project_id

    assert_receive {:handled, %DeliverLogStream.Stop{attributes: %{result: :ok}} = stopped, :stop}
    assert is_integer(stopped.measurements.duration)
  end

  test "reports the exception phase", %{project_id: project_id} do
    event = %DeliverLogStream{attributes: %DeliverLogStream.Attributes{project_id: project_id}}

    assert_raise RuntimeError, fn -> Trogon.Telemetry.span(event, fn -> raise "boom" end) end

    assert_receive {:handled, %DeliverLogStream.Exception{attributes: %{kind: :error}}, :exception}
  end

  test "attaching twice is a no-op" do
    assert :ok = DeliveryRecorder.attach(%{pid: self()})
  end
end
