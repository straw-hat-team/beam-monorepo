defmodule EventStoreDashboard.Components.StreamsTable do
  @moduledoc false

  use Phoenix.Component

  import Phoenix.LiveDashboard.PageBuilder

  alias EventStore.Sql.Statements
  alias EventStoreDashboard.Components.{EventLink, Pagination, TableParams}
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  @page_param :streams_page
  @sort_columns ~w(stream_id stream_uuid stream_version created_at deleted_at)

  attr(:ctx, Context, required: true)
  attr(:page, PageBuilder, required: true)
  attr(:socket, Socket, required: true)
  attr(:page_number, :integer, required: true)

  def render(assigns) do
    result =
      paginate_streams(
        assigns.ctx,
        assigns.page.node,
        assigns.page_number,
        assigns.page.params
      )

    assigns =
      assign(assigns,
        page_param: @page_param,
        result: result
      )

    ~H"""
    <.live_table
      id="event_store_streams_table"
      page={@page}
      title="Streams"
      default_sort_by={:stream_id}
      row_attrs={&row_attrs/1}
      row_fetcher={&fetch_rows(&1, &2, @result)}
    >
      <:col field={:stream_id} header="Id" sortable={:asc} />
      <:col field={:stream_uuid} header="Stream" sortable={:asc} />
      <:col field={:stream_version} header="Stream Version" sortable={:asc} :let={row}>
        <EventLink.render
          socket={@socket}
          page={@page}
          ctx={@ctx}
          stream_uuid={row[:stream_uuid]}
          event_number={row[:stream_version]}
          stop_propagation
        />
      </:col>
      <:col field={:created_at} header="Created at" sortable={:asc} />
      <:col field={:deleted_at} header="Deleted at" sortable={:asc} />
    </.live_table>
    <Pagination.render
      id="streams-pagination"
      param={@page_param}
      page_number={@page_number}
      total_pages={@result.total_pages}
      socket={@socket}
      page={@page}
    />
    """
  end

  # Bypass EventStore.paginate_streams/1: it wraps :search as "%foo%" (substring,
  # cannot use a btree index on stream_uuid). Here we issue our own Postgrex
  # queries with prefix-only matching ("foo%"), which is index-friendly.
  defp paginate_streams(%Context{} = ctx, node, page_number, url_params) do
    sort_by = TableParams.parse_sort_by(url_params, @sort_columns, :stream_id)
    sort_dir = TableParams.parse_sort_dir(url_params, :asc)
    limit = TableParams.parse_limit(url_params)

    search_term = url_params |> TableParams.parse_search() |> prefix_pattern()
    offset = (page_number - 1) * limit

    with {:ok, total_entries} <- count_streams(node, ctx, search_term),
         {:ok, rows} <-
           query_streams(node, ctx, sort_by, sort_dir, search_term, limit, offset) do
      total_pages = if total_entries == 0, do: 0, else: div(total_entries - 1, limit) + 1

      %{
        entries: Enum.map(rows, &row_to_stream/1),
        total_entries: total_entries,
        total_pages: total_pages
      }
    else
      _ -> %{entries: [], total_entries: 0, total_pages: 0}
    end
  end

  defp count_streams(node, %Context{} = ctx, search_term) do
    sql = IO.iodata_to_binary(Statements.count_streams(ctx.schema))

    case :rpc.call(node, Postgrex, :query, [ctx.conn, sql, [search_term]]) do
      {:ok, %Postgrex.Result{rows: [[count]]}} -> {:ok, count}
      _ -> :error
    end
  end

  defp query_streams(node, %Context{} = ctx, sort_by, sort_dir, search_term, limit, offset) do
    sql =
      IO.iodata_to_binary(Statements.query_streams(ctx.schema, Atom.to_string(sort_by), sort_dir_sql(sort_dir)))

    case :rpc.call(node, Postgrex, :query, [ctx.conn, sql, [search_term, limit, offset]]) do
      {:ok, %Postgrex.Result{rows: rows}} -> {:ok, rows}
      _ -> :error
    end
  end

  defp sort_dir_sql(:asc), do: "ASC"
  defp sort_dir_sql(:desc), do: "DESC"

  defp row_to_stream([stream_id, stream_uuid, stream_version, created_at, deleted_at]) do
    %{
      stream_id: stream_id,
      stream_uuid: stream_uuid,
      stream_version: stream_version || 0,
      created_at: created_at,
      deleted_at: deleted_at,
      status: if(is_nil(deleted_at), do: :created, else: :deleted)
    }
  end

  defp prefix_pattern(nil), do: "%"
  defp prefix_pattern(search), do: search <> "%"

  defp fetch_rows(_params, _node, result), do: {result.entries, result.total_entries}

  defp row_attrs(row) do
    [
      {"phx-click", "show_stream"},
      {"phx-value-stream", row[:stream_uuid]},
      {"phx-page-loading", true}
    ]
  end
end
