defmodule EventStoreDashboard.Components.SnapshotModal do
  @moduledoc false

  use Phoenix.Component

  alias EventStoreDashboard.Components.{DataField, EventLink}
  alias EventStoreDashboard.{Params, Repo}
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  @inspect_opts [limit: :infinity, printable_limit: :infinity, pretty: true]

  attr(:page, PageBuilder, required: true)
  attr(:ctx, Context, required: true)
  attr(:source_uuid, :string, required: true)
  attr(:socket, Socket, required: true)

  def render(assigns) do
    snapshot = fetch_snapshot(assigns.page.node, assigns.ctx, assigns.source_uuid)

    assigns =
      assign(assigns,
        snapshot: snapshot,
        inspect_opts: @inspect_opts
      )

    ~H"""
    <div>
      <div :if={@snapshot} class="tabular-info">
        <table class="table table-hover tabular-info-table">
          <tbody>
            <tr>
              <td class="border-top-0">Stream</td>
              <td class="border-top-0">
                <.link
                  patch={stream_modal_path(@socket, @page, @ctx, @snapshot.source_uuid)}
                  class="es-modal-trigger"
                >
                  {@snapshot.source_uuid}
                </.link>
              </td>
            </tr>
            <tr>
              <td>Type</td>
              <td><pre>{@snapshot.source_type}</pre></td>
            </tr>
            <tr>
              <td>Stream Version</td>
              <td>
                <EventLink.render
                  socket={@socket}
                  page={@page}
                  ctx={@ctx}
                  stream_uuid={@snapshot.source_uuid}
                  event_number={@snapshot.source_version}
                />
              </td>
            </tr>
            <tr>
              <td>Created at</td>
              <td><pre>{@snapshot.created_at}</pre></td>
            </tr>
            <DataField.row label="Data" value={@snapshot.data} inspect_opts={@inspect_opts} />
            <DataField.row label="Metadata" value={@snapshot.metadata} inspect_opts={@inspect_opts} />
          </tbody>
        </table>
      </div>
      <div :if={is_nil(@snapshot)} class="alert alert-warning" role="alert">
        Snapshot not found.
      </div>
    </div>
    """
  end

  defp fetch_snapshot(node, %Context{} = ctx, source_uuid) do
    case Repo.fetch_snapshot(node, ctx, source_uuid) do
      {:ok, snapshot} -> snapshot
      _ -> nil
    end
  end

  defp stream_modal_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      stream_modal: stream_uuid,
      snapshot_uuid: nil
    })
  end
end
