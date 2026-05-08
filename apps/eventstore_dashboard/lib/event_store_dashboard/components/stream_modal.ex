defmodule EventStoreDashboard.Components.StreamModal do
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
  attr(:stream_uuid, :string, required: true)
  attr(:socket, Socket, required: true)

  def render(assigns) do
    stream = fetch_stream(assigns.page.node, assigns.ctx, assigns.stream_uuid)
    snapshot = fetch_snapshot(assigns.page.node, assigns.ctx, assigns.stream_uuid)
    assigns = assign(assigns, stream: stream, snapshot: snapshot)

    ~H"""
    <div>
      <%= if @stream do %>
        <div class="tabular-info">
          <table class="table table-hover tabular-info-table">
            <tbody>
              <tr>
                <td class="border-top-0">Stream</td>
                <td class="border-top-0"><pre>{@stream.stream_uuid}</pre></td>
              </tr>
              <tr>
                <td>ID</td>
                <td><pre>{@stream.stream_id}</pre></td>
              </tr>
              <tr>
                <td>Stream Version</td>
                <td>
                  <EventLink.render
                    socket={@socket}
                    page={@page}
                    ctx={@ctx}
                    stream_uuid={@stream.stream_uuid}
                    event_number={@stream.stream_version}
                  />
                </td>
              </tr>
              <tr>
                <td>Status</td>
                <td><.status_badge status={@stream.status} /></td>
              </tr>
              <tr :if={@snapshot}>
                <td>Snapshot</td>
                <td>
                  <.link
                    patch={snapshot_modal_path(@socket, @page, @ctx, @snapshot.source_uuid)}
                    class="es-modal-trigger"
                  >
                    @{@snapshot.source_version}
                  </.link>
                  <span :if={snapshot_lag(@stream, @snapshot) > 0} class="badge badge-warning ml-2">
                    {snapshot_lag(@stream, @snapshot)} events behind
                  </span>
                </td>
              </tr>
              <tr>
                <td>Created at</td>
                <td><pre>{@stream.created_at}</pre></td>
              </tr>
              <tr :if={@stream.deleted_at}>
                <td>Deleted at</td>
                <td><pre>{@stream.deleted_at}</pre></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="modal-footer">
          <.link
            patch={view_events_path(@socket, @page, @ctx, @stream.stream_uuid)}
            class="btn btn-sm btn-primary"
          >
            View events
          </.link>
        </div>
      <% else %>
        <div class="alert alert-warning" role="alert">
          Stream not found.
        </div>
      <% end %>
    </div>
    """
  end

  attr(:status, :atom, required: true)

  defp status_badge(%{status: :deleted} = assigns) do
    ~H|<span class="badge badge-danger">deleted</span>|
  end

  defp status_badge(%{status: :created} = assigns) do
    ~H|<span class="badge badge-success">created</span>|
  end

  defp status_badge(assigns) do
    ~H|<span class="badge badge-secondary">unknown</span>|
  end

  defp fetch_stream(node, %Context{} = ctx, stream_uuid) do
    case Repo.fetch_stream(node, ctx, stream_uuid) do
      {:ok, stream} -> stream
      _ -> nil
    end
  end

  defp fetch_snapshot(_node, _ctx, "$all"), do: nil

  defp fetch_snapshot(node, %Context{} = ctx, stream_uuid) do
    case Repo.fetch_snapshot_summary(node, ctx, stream_uuid) do
      {:ok, snapshot} -> snapshot
      _ -> nil
    end
  end

  defp snapshot_lag(stream, snapshot) do
    max((stream.stream_version || 0) - (snapshot.source_version || 0), 0)
  end

  defp snapshot_modal_path(socket, page, %Context{} = ctx, source_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      nav: "snapshots",
      snapshot_uuid: source_uuid,
      stream_modal: nil
    })
  end

  defp view_events_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      nav: "events",
      stream: stream_uuid
    })
  end
end
