defmodule EventStoreDashboard.Components.EventsTable do
  @moduledoc false

  use Phoenix.Component

  import Phoenix.LiveDashboard.PageBuilder

  alias EventStoreDashboard.Components.{EventLink, EventModal, Pagination, TableParams}
  alias EventStoreDashboard.{Params, Repo}
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  @page_param :events_page

  attr(:ctx, Context, required: true)
  attr(:page, PageBuilder, required: true)
  attr(:socket, Socket, required: true)
  attr(:page_number, :integer, required: true)
  attr(:event_number, :integer, default: nil)
  attr(:stream_uuid, :string, required: true)
  attr(:correlation_id, :string, default: nil)
  attr(:causation_id, :string, default: nil)

  def render(assigns) do
    params = assigns.page.params
    sort_dir = TableParams.parse_sort_dir(params, :asc)
    limit = TableParams.parse_limit(params)
    filter = active_filter(assigns)
    type_filter = event_type_pattern(TableParams.parse_search(params))

    result = fetch_result(filter, assigns, sort_dir, type_filter, limit)

    assigns =
      assign(assigns,
        page_param: @page_param,
        result: result,
        filter: filter
      )

    ~H"""
    <.filter_card
      :if={@filter}
      filter={@filter}
      ctx={@ctx}
      socket={@socket}
      page={@page}
    />
    <.live_table
      id="event_store_events_table"
      page={@page}
      title={events_title(@filter, @stream_uuid)}
      default_sort_by={:event_number}
      rows_name="events"
      row_attrs={&row_attrs(&1, @filter, @stream_uuid)}
      row_fetcher={&fetch_rows(&1, &2, @result)}
    >
      <:col :if={is_nil(@filter)} field={:event_number} header="Position" sortable={:asc} />
      <:col :if={is_nil(@filter)} field={:stream_version} header="Stream Version" :let={row}>
        <EventLink.render
          socket={@socket}
          page={@page}
          ctx={@ctx}
          stream_uuid={row[:stream_uuid]}
          event_number={row[:stream_version]}
          stop_propagation
        />
      </:col>
      <:col :if={not is_nil(@filter)} field={:event_number} header="Stream Version" sortable={:asc} :let={row}>
        <EventLink.render
          socket={@socket}
          page={@page}
          ctx={@ctx}
          stream_uuid={row[:stream_uuid]}
          event_number={row[:stream_version]}
          stop_propagation
        />
      </:col>
      <:col field={:event_type} header="Type" />
      <:col :if={not match?({:stream, _}, @filter)} field={:stream_uuid} header="Stream" :let={row}>
        <.link
          patch={stream_modal_path(@socket, @page, @ctx, row[:stream_uuid])}
          onclick="event.stopPropagation()"
          class="es-modal-trigger"
        >
          {row[:stream_uuid]}
        </.link>
      </:col>
      <:col field={:created_at} header="Created at" />
      <:col field={:event_id} header="Event ID" />
    </.live_table>
    <Pagination.render
      id="events-pagination"
      param={@page_param}
      page_number={@page_number}
      total_pages={@result.total_pages}
      socket={@socket}
      page={@page}
    />
    <.live_modal
      :if={@event_number}
      id="event-modal"
      title="Event"
      return_to={modal_return_to(@socket, @page)}
    >
      <.live_component
        module={EventModal}
        id="event-modal-content"
        page={@page}
        ctx={@ctx}
        stream_uuid={@stream_uuid}
        event_number={@event_number}
        return_to={modal_return_to(@socket, @page)}
      />
    </.live_modal>
    """
  end

  defp fetch_result({kind, value}, assigns, _sort_dir, type_filter, limit)
       when kind in [:correlation, :causation] do
    paginate_by_id(
      assigns.ctx,
      assigns.page.node,
      id_column(kind),
      value,
      type_filter,
      assigns.page_number,
      limit
    )
  end

  defp fetch_result(_filter, assigns, sort_dir, type_filter, limit) do
    read_stream(
      assigns.ctx,
      assigns.page.node,
      assigns.stream_uuid,
      sort_dir,
      type_filter,
      assigns.page_number,
      limit
    )
  end

  defp id_column(:correlation), do: :correlation_id
  defp id_column(:causation), do: :causation_id

  defp active_filter(%{correlation_id: id}) when is_binary(id), do: {:correlation, id}
  defp active_filter(%{causation_id: id}) when is_binary(id), do: {:causation, id}
  defp active_filter(%{stream_uuid: "$all"}), do: nil
  defp active_filter(%{stream_uuid: uuid}) when is_binary(uuid), do: {:stream, uuid}
  defp active_filter(_), do: nil

  defp events_title({_, _}, _), do: "Events"
  defp events_title(nil, _), do: "All stream events"

  attr(:filter, :any, required: true)
  attr(:ctx, Context, required: true)
  attr(:socket, Socket, required: true)
  attr(:page, PageBuilder, required: true)

  defp filter_card(assigns) do
    ~H"""
    <div class="card mb-4">
      <div class="card-body">
        <div class="d-flex justify-content-between align-items-center">
          <div>
            <strong>{filter_label(@filter)}:</strong>
            <%= case @filter do %>
              <% {:stream, uuid} -> %>
                <.link
                  patch={stream_modal_path(@socket, @page, @ctx, uuid)}
                  class="ml-2 es-modal-trigger"
                >
                  <code>{uuid}</code>
                </.link>
              <% {_, value} -> %>
                <code class="ml-2">{value}</code>
            <% end %>
          </div>
          <.link
            patch={clear_filter_path(@socket, @page, @filter)}
            class="btn btn-sm btn-outline-secondary"
          >
            Clear filter
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp filter_label({:correlation, _}), do: "Correlation ID"
  defp filter_label({:causation, _}), do: "Causation ID"
  defp filter_label({:stream, _}), do: "Stream"

  defp event_type_pattern(nil), do: nil
  defp event_type_pattern(""), do: nil
  defp event_type_pattern(value), do: "%" <> value <> "%"

  defp stream_modal_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      stream_modal: stream_uuid
    })
  end

  defp modal_return_to(socket, page) do
    live_dashboard_path(socket, page, event: nil)
  end

  defp clear_filter_path(socket, page, {:stream, _}) do
    live_dashboard_path(socket, page,
      stream: nil,
      event: nil,
      events_page: nil
    )
  end

  defp clear_filter_path(socket, page, {kind, _}) when kind in [:correlation, :causation] do
    live_dashboard_path(socket, page,
      correlation_id: nil,
      causation_id: nil,
      event: nil,
      events_page: nil
    )
  end

  defp read_stream(%Context{} = ctx, node, stream_uuid, sort_dir, type_filter, page_number, limit) do
    offset = (page_number - 1) * limit

    case Repo.fetch_stream(node, ctx, stream_uuid) do
      {:ok, stream} ->
        total_entries = count_stream_events(node, ctx, stream, type_filter)
        total_pages = total_pages(total_entries, limit)
        entries = fetch_stream_entries(node, ctx, stream.stream_id, sort_dir, type_filter, limit, offset)

        %{entries: entries, total_entries: total_entries, total_pages: total_pages}

      _ ->
        %{entries: [], total_entries: 0, total_pages: 0}
    end
  end

  defp count_stream_events(_node, _ctx, stream, nil), do: stream.stream_version

  defp count_stream_events(node, %Context{} = ctx, stream, pattern) do
    case Repo.count_events_in_stream(node, ctx, stream.stream_id, pattern) do
      {:ok, n} -> n
      _ -> 0
    end
  end

  defp fetch_stream_entries(node, %Context{} = ctx, stream_id, sort_dir, type_filter, limit, offset) do
    case Repo.query_events_in_stream(node, ctx, stream_id, sort_dir, type_filter, limit, offset) do
      {:ok, rows} -> Enum.map(rows, &Repo.row_to_event(&1, ctx))
      _ -> []
    end
  end

  # Filter events by correlation_id or causation_id by querying the events table
  # directly. There's no default index on these columns — fine for diagnostic
  # use, slow on huge tables.
  defp paginate_by_id(%Context{} = ctx, node, column, value, type_filter, page_number, limit) do
    offset = (page_number - 1) * limit

    with {:ok, total} <-
           Repo.count_events_by_id(node, ctx, column, value, type_filter),
         {:ok, rows} <-
           query_events_by_id(node, ctx, column, value, type_filter, limit, offset) do
      total_pages = total_pages(total, limit)

      %{
        entries: Enum.map(rows, &Repo.row_to_event(&1, ctx)),
        total_entries: total,
        total_pages: total_pages
      }
    else
      _ -> %{entries: [], total_entries: 0, total_pages: 0}
    end
  end

  defp query_events_by_id(node, %Context{} = ctx, column, value, type_filter, limit, offset) do
    with {:ok, uuid} <- Repo.string_to_uuid(value) do
      {type_clause, params} = Repo.event_type_clause(type_filter, [uuid, limit, offset], 4)

      sql = """
      SELECT
        se.stream_version,
        e.event_id,
        s.stream_uuid,
        se.original_stream_version,
        e.event_type,
        e.correlation_id,
        e.causation_id,
        e.data,
        e.metadata,
        e.created_at
      FROM #{ctx.schema}.events e
      LEFT JOIN #{ctx.schema}.stream_events se
        ON se.event_id = e.event_id
        AND se.stream_id = se.original_stream_id
      LEFT JOIN #{ctx.schema}.streams s ON s.stream_id = se.original_stream_id
      WHERE e.#{column} = $1#{type_clause}
      ORDER BY e.created_at ASC
      LIMIT $2 OFFSET $3;
      """

      Repo.query(node, ctx.conn, sql, params)
    end
  end

  defp total_pages(0, _limit), do: 0
  defp total_pages(total, limit), do: div(total - 1, limit) + 1

  defp fetch_rows(_params, _node, result), do: {result.entries, result.total_entries}

  defp row_attrs(row, nil, stream_uuid) do
    [
      {"phx-click", "show_event"},
      {"phx-value-stream", stream_uuid},
      {"phx-value-event", row[:event_number]},
      {"phx-page-loading", true}
    ]
  end

  defp row_attrs(row, _filter, _stream_uuid) do
    [
      {"phx-click", "show_event"},
      {"phx-value-stream", row[:stream_uuid]},
      {"phx-value-event", row[:stream_version]},
      {"phx-page-loading", true}
    ]
  end
end
