defmodule EventStoreDashboard.Components.EventLink do
  @moduledoc false

  use Phoenix.Component

  alias EventStoreDashboard.Params
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  attr(:socket, Socket, required: true)
  attr(:page, PageBuilder, required: true)
  attr(:ctx, Context, required: true)
  attr(:stream_uuid, :string, required: true)
  attr(:event_number, :integer, default: nil)
  attr(:stop_propagation, :boolean, default: false)

  def render(assigns) do
    ~H"""
    <.link
      :if={is_integer(@event_number) and @event_number > 0}
      patch={event_path(@socket, @page, @ctx, @stream_uuid, @event_number)}
      onclick={if @stop_propagation, do: "event.stopPropagation()"}
      class="es-modal-trigger"
    >
      @{@event_number}
    </.link>
    <span :if={not (is_integer(@event_number) and @event_number > 0)}>@{@event_number}</span>
    """
  end

  defp event_path(socket, page, %Context{} = ctx, stream_uuid, event_number) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      nav: "events",
      stream: stream_uuid,
      event: event_number
    })
  end
end
