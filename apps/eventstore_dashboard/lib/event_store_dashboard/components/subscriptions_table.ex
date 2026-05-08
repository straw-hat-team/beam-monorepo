defmodule EventStoreDashboard.Components.SubscriptionsTable do
  @moduledoc false

  use Phoenix.LiveComponent

  import Phoenix.LiveDashboard.PageBuilder

  alias EventStoreDashboard.Components.{EventLink, Pagination, SubscriptionModal, TableParams}
  alias EventStoreDashboard.{Params, Repo, Subscription}
  alias EventStoreDashboard.Repo.Context

  @page_param :subscriptions_page
  @sort_columns ~w(subscription_id stream_uuid subscription_name last_seen created_at)

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :lag_snapshot, %{})}
  end

  @impl true
  def update(assigns, socket) do
    result =
      paginate_subscriptions(
        assigns.ctx,
        assigns.page.node,
        assigns.page_number,
        assigns.page.params
      )

    prev_snapshot = socket.assigns.lag_snapshot

    entries = Enum.map(result.entries, &apply_lag_trend(&1, prev_snapshot))
    next_snapshot = Map.new(entries, &subscription_lag/1)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       page_param: @page_param,
       result: %{result | entries: entries},
       lag_snapshot: next_snapshot
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.live_table
        id="event_store_subscriptions_table"
        page={@page}
        title="Subscriptions"
        default_sort_by={:subscription_id}
        rows_name="subscriptions"
        row_attrs={&row_attrs/1}
        row_fetcher={&fetch_rows(&1, &2, @result)}
      >
        <:col field={:subscription_id} header="ID" sortable={:asc} />
        <:col field={:stream_uuid} header="Stream" sortable={:asc} :let={row}>
          <.link
            patch={stream_modal_path(@socket, @page, @ctx, row[:stream_uuid])}
            onclick="event.stopPropagation()"
            class="es-modal-trigger"
          >
            {row[:stream_uuid]}
          </.link>
        </:col>
        <:col field={:subscription_name} header="Name" sortable={:asc} />
        <:col field={:lag} header="Lag" :let={row}>
          <.lag_badge lag={row[:lag]} trend={row[:trend]} />
        </:col>
        <:col field={:last_seen} header="Last seen" sortable={:asc} :let={row}>
          <EventLink.render
            socket={@socket}
            page={@page}
            ctx={@ctx}
            stream_uuid={row[:stream_uuid]}
            event_number={row[:last_seen]}
            stop_propagation
          />
        </:col>
        <:col field={:created_at} header="Created at" sortable={:asc} />
      </.live_table>
      <Pagination.render
        id="subscriptions-pagination"
        param={@page_param}
        page_number={@page_number}
        total_pages={@result.total_pages}
        socket={@socket}
        page={@page}
      />
      <.live_modal
        :if={@subscription_id}
        id="subscription-modal"
        title="Subscription"
        return_to={modal_return_to(@socket, @page)}
      >
        <SubscriptionModal.render
          page={@page}
          ctx={@ctx}
          subscription_id={@subscription_id}
          socket={@socket}
        />
      </.live_modal>
    </div>
    """
  end

  attr(:lag, :integer, required: true)
  attr(:trend, :atom, required: true)

  defp lag_badge(assigns) do
    ~H"""
    <span class={"badge #{lag_class(@lag)}"}>
      {@lag}<.trend_arrow trend={@trend} />
    </span>
    """
  end

  attr(:trend, :atom, required: true)

  defp trend_arrow(%{trend: :catching_up} = assigns),
    do: ~H|<span title="Catching up" class="ml-1">&#x2193;</span>|

  defp trend_arrow(%{trend: :falling_behind} = assigns),
    do: ~H|<span title="Falling behind" class="ml-1">&#x2191;</span>|

  defp trend_arrow(assigns), do: ~H||

  defp lag_trend(nil, _current), do: :unknown
  defp lag_trend(prev, current) when current < prev, do: :catching_up
  defp lag_trend(prev, current) when current > prev, do: :falling_behind
  defp lag_trend(_prev, _current), do: :stable

  defp lag_class(0), do: "badge-success"
  defp lag_class(lag) when lag < 100, do: "badge-secondary"
  defp lag_class(lag) when lag < 10_000, do: "badge-warning"
  defp lag_class(_), do: "badge-danger"

  defp paginate_subscriptions(nil, _node, _page_number, _url_params),
    do: %{entries: [], total_entries: 0, total_pages: 0}

  defp paginate_subscriptions(%Context{} = ctx, node, page_number, url_params) do
    sort_by = TableParams.parse_sort_by(url_params, @sort_columns, :subscription_id)
    sort_dir = TableParams.parse_sort_dir(url_params, :asc)
    limit = TableParams.parse_limit(url_params)

    search_term = url_params |> TableParams.parse_search() |> like_pattern()
    offset = (page_number - 1) * limit

    with {:ok, total_entries} <- count_subscriptions(node, ctx, search_term),
         {:ok, rows} <-
           query_subscriptions(
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
        entries: Enum.map(rows, &row_to_subscription/1),
        total_entries: total_entries,
        total_pages: total_pages
      }
    else
      _ -> %{entries: [], total_entries: 0, total_pages: 0}
    end
  end

  defp count_subscriptions(node, %Context{} = ctx, search_term) do
    {where, params} = search_clause(search_term, [], 1)
    sql = "SELECT COUNT(*) FROM #{ctx.schema}.subscriptions s#{where};"

    case Repo.query(node, ctx.conn, sql, params) do
      {:ok, [[count]]} -> {:ok, count}
      _ -> :error
    end
  end

  defp query_subscriptions(node, %Context{} = ctx, sort_by, sort_dir, search_term, limit, offset) do
    {where, params} = search_clause(search_term, [limit, offset], 3)

    sql = """
    SELECT
      s.subscription_id,
      s.stream_uuid,
      s.subscription_name,
      s.last_seen,
      s.created_at,
      st.stream_version
    FROM #{ctx.schema}.subscriptions s
    LEFT JOIN #{ctx.schema}.streams st ON st.stream_uuid = s.stream_uuid#{where}
    ORDER BY s.#{sort_by} #{sort_dir_sql(sort_dir)}
    LIMIT $1 OFFSET $2;
    """

    Repo.query(node, ctx.conn, sql, params)
  end

  defp row_to_subscription([
         subscription_id,
         stream_uuid,
         subscription_name,
         last_seen,
         created_at,
         stream_version
       ]) do
    version = stream_version || 0
    seen = last_seen || 0

    %Subscription{
      subscription_id: subscription_id,
      stream_uuid: stream_uuid,
      subscription_name: subscription_name,
      last_seen: last_seen,
      stream_version: version,
      lag: max(version - seen, 0),
      created_at: created_at
    }
  end

  defp apply_lag_trend(%Subscription{} = entry, prev_snapshot) do
    %{entry | trend: lag_trend(prev_snapshot[entry.subscription_id], entry.lag)}
  end

  defp subscription_lag(%Subscription{} = entry), do: {entry.subscription_id, entry.lag}

  defp fetch_rows(_params, _node, result), do: {result.entries, result.total_entries}

  defp like_pattern(nil), do: nil
  defp like_pattern(term), do: "%" <> term <> "%"

  defp search_clause(nil, base_params, _index), do: {"", base_params}

  defp search_clause(term, base_params, index),
    do: {" WHERE s.subscription_name ILIKE $#{index} OR s.stream_uuid ILIKE $#{index}", base_params ++ [term]}

  defp sort_dir_sql(:asc), do: "ASC"
  defp sort_dir_sql(:desc), do: "DESC"

  defp row_attrs(row) do
    [
      {"phx-click", "show_subscription"},
      {"phx-value-subscription_id", row[:subscription_id]},
      {"phx-page-loading", true}
    ]
  end

  defp modal_return_to(socket, page) do
    live_dashboard_path(socket, page, subscription_id: nil)
  end

  defp stream_modal_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      stream_modal: stream_uuid,
      subscription_id: nil
    })
  end
end
