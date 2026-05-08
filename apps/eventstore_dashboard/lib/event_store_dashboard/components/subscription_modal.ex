defmodule EventStoreDashboard.Components.SubscriptionModal do
  @moduledoc false

  use Phoenix.Component

  alias EventStoreDashboard.Components.EventLink
  alias EventStoreDashboard.Params
  alias EventStoreDashboard.Repo
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  attr(:page, PageBuilder, required: true)
  attr(:ctx, Context, required: true)
  attr(:subscription_id, :integer, required: true)
  attr(:socket, Socket, required: true)

  @pending_limit 10

  def render(assigns) do
    subscription = fetch_subscription(assigns.page.node, assigns.ctx, assigns.subscription_id)
    pending = fetch_pending(assigns.page.node, assigns.ctx, subscription)

    assigns =
      assign(assigns,
        subscription: subscription,
        pending: pending,
        pending_limit: @pending_limit
      )

    ~H"""
    <div>
      <%= if @subscription do %>
        <div class="tabular-info">
          <table class="table table-hover tabular-info-table">
            <tbody>
              <tr>
                <td class="border-top-0">ID</td>
                <td class="border-top-0"><pre>{@subscription.subscription_id}</pre></td>
              </tr>
              <tr>
                <td>Name</td>
                <td><pre>{@subscription.subscription_name}</pre></td>
              </tr>
              <tr>
                <td>Stream</td>
                <td>
                  <.link
                    patch={stream_modal_path(@socket, @page, @ctx, @subscription.stream_uuid)}
                    class="es-modal-trigger"
                  >
                    {@subscription.stream_uuid}
                  </.link>
                </td>
              </tr>
              <tr>
                <td>Last seen</td>
                <td>
                  <EventLink.render
                    socket={@socket}
                    page={@page}
                    ctx={@ctx}
                    stream_uuid={@subscription.stream_uuid}
                    event_number={@subscription.last_seen}
                  />
                </td>
              </tr>
              <tr>
                <td>Stream Version</td>
                <td>
                  <EventLink.render
                    socket={@socket}
                    page={@page}
                    ctx={@ctx}
                    stream_uuid={@subscription.stream_uuid}
                    event_number={@subscription.stream_version}
                  />
                </td>
              </tr>
              <tr>
                <td>Lag</td>
                <td><pre>{@subscription.lag}</pre></td>
              </tr>
              <tr>
                <td>Created at</td>
                <td><pre>{@subscription.created_at}</pre></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@subscription.lag > 0} class="mt-3">
          <h6 class="mb-2">
            Next pending events
            <small class="text-muted">
              (showing up to {@pending_limit} of {@subscription.lag})
            </small>
          </h6>
          <p :if={@pending == []} class="text-muted small mb-0">
            Could not load pending events.
          </p>
          <table :if={@pending != []} class="table table-sm tabular-info-table">
            <thead>
              <tr>
                <th>{position_header(@subscription.stream_uuid)}</th>
                <th>Type</th>
                <th>Created at</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={event <- @pending}>
                <td>
                  <EventLink.render
                    socket={@socket}
                    page={@page}
                    ctx={@ctx}
                    stream_uuid={@subscription.stream_uuid}
                    event_number={event.event_number}
                  />
                </td>
                <td><pre class="mb-0">{event.event_type}</pre></td>
                <td><pre class="mb-0">{event.created_at}</pre></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="modal-footer">
          <.link
            patch={view_events_path(@socket, @page, @ctx, @subscription.stream_uuid)}
            class="btn btn-sm btn-primary"
          >
            View events on this stream
          </.link>
        </div>
      <% else %>
        <div class="alert alert-warning" role="alert">
          Subscription not found.
        </div>
      <% end %>
    </div>
    """
  end

  defp fetch_subscription(node, %Context{} = ctx, subscription_id) do
    case Repo.fetch_subscription_by_id(node, ctx, subscription_id) do
      {:ok, subscription} -> subscription
      _ -> nil
    end
  end

  defp fetch_pending(_node, _ctx, nil), do: []
  defp fetch_pending(_node, _ctx, %{lag: 0}), do: []

  defp fetch_pending(node, %Context{} = ctx, subscription) do
    with {:ok, stream} <- Repo.fetch_stream(node, ctx, subscription.stream_uuid),
         {:ok, rows} <-
           Repo.query_events_after_version(
             node,
             ctx,
             stream.stream_id,
             subscription.last_seen || 0,
             @pending_limit
           ) do
      Enum.map(rows, &Repo.row_to_event(&1, ctx))
    else
      _ -> []
    end
  end

  defp position_header("$all"), do: "Position"
  defp position_header(_), do: "Stream Version"

  defp view_events_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      nav: "events",
      stream: stream_uuid
    })
  end

  defp stream_modal_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      stream_modal: stream_uuid,
      subscription_id: nil
    })
  end
end
