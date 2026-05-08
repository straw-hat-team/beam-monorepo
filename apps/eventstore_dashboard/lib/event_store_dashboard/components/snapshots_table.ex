defmodule EventStoreDashboard.Components.SnapshotsTable do
  @moduledoc false

  use Phoenix.LiveComponent

  import Phoenix.LiveDashboard.PageBuilder

  alias EventStoreDashboard.Components.{EventLink, Pagination, SnapshotModal, TableParams}
  alias EventStoreDashboard.Repo
  alias EventStoreDashboard.Repo.Context

  @page_param :snapshots_page
  @sort_columns ~w(source_uuid source_type source_version created_at)

  @impl true
  def update(assigns, socket) do
    result =
      paginate_snapshots(
        assigns.ctx,
        assigns.page.node,
        assigns.page_number,
        assigns.page.params
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(page_param: @page_param, result: result)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_table
        id="event_store_snapshots_table"
        page={@page}
        title="Snapshots"
        default_sort_by={:created_at}
        rows_name="snapshots"
        row_attrs={&row_attrs/1}
        row_fetcher={&fetch_rows(&1, &2, @result)}
      >
        <:col field={:source_uuid} header="Stream" sortable={:asc} />
        <:col field={:source_type} header="Type" sortable={:asc} />
        <:col field={:source_version} header="Stream Version" sortable={:asc} :let={row}>
          <EventLink.render
            socket={@socket}
            page={@page}
            ctx={@ctx}
            stream_uuid={row[:source_uuid]}
            event_number={row[:source_version]}
            stop_propagation
          />
        </:col>
        <:col field={:created_at} header="Created at" sortable={:desc} />
      </.live_table>
      <Pagination.render
        id="snapshots-pagination"
        param={@page_param}
        page_number={@page_number}
        total_pages={@result.total_pages}
        socket={@socket}
        page={@page}
      />
      <.live_modal
        :if={@snapshot_uuid}
        id="snapshot-modal"
        title="Snapshot"
        return_to={modal_return_to(@socket, @page)}
      >
        <SnapshotModal.render
          page={@page}
          ctx={@ctx}
          source_uuid={@snapshot_uuid}
          socket={@socket}
        />
      </.live_modal>
    </div>
    """
  end

  defp paginate_snapshots(nil, _node, _page_number, _url_params),
    do: %{entries: [], total_entries: 0, total_pages: 0}

  defp paginate_snapshots(%Context{} = ctx, node, page_number, url_params) do
    sort_by = TableParams.parse_sort_by(url_params, @sort_columns, :created_at)
    sort_dir = TableParams.parse_sort_dir(url_params, :desc)
    limit = TableParams.parse_limit(url_params)

    search_term = url_params |> TableParams.parse_search() |> like_pattern()
    offset = (page_number - 1) * limit

    with {:ok, total_entries} <- Repo.count_snapshots(node, ctx, search_term),
         {:ok, rows} <-
           Repo.query_snapshots(
             node,
             ctx,
             sort_by,
             sort_dir,
             search_term,
             limit,
             offset
           ) do
      total_pages = if total_entries == 0, do: 0, else: div(total_entries - 1, limit) + 1

      %{
        entries: Enum.map(rows, &Repo.row_to_snapshot_summary/1),
        total_entries: total_entries,
        total_pages: total_pages
      }
    else
      _ -> %{entries: [], total_entries: 0, total_pages: 0}
    end
  end

  defp like_pattern(nil), do: nil
  defp like_pattern(term), do: "%" <> term <> "%"

  defp fetch_rows(_params, _node, result), do: {result.entries, result.total_entries}

  defp row_attrs(row) do
    [
      {"phx-click", "show_snapshot"},
      {"phx-value-source", row.source_uuid},
      {"phx-page-loading", true}
    ]
  end

  defp modal_return_to(socket, page) do
    live_dashboard_path(socket, page, snapshot_uuid: nil)
  end
end
