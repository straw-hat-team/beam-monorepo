defmodule EventStoreDashboard do
  @moduledoc false

  alias EventStoreDashboard.Components.{
    EventsTable,
    SnapshotsTable,
    StreamModal,
    StreamsTable,
    SubscriptionsTable
  }

  alias EventStoreDashboard.{Params, Repo}
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder

  use PageBuilder, refresher?: true

  @minimum_event_store_version "1.4.0"

  @disabled_link "https://hexdocs.pm/eventstore_dashboard"
  @page_title "EventStores"

  @impl PageBuilder
  def init(opts) do
    event_stores = opts[:event_stores] || :auto_discover

    {:ok, %{event_stores: event_stores}, application: :eventstore}
  end

  @impl PageBuilder
  def menu_link(%{event_stores: event_stores}, _capabilities) do
    if event_stores == [] do
      {:disabled, @page_title, @disabled_link}
    else
      {:ok, @page_title}
    end
  end

  @impl PageBuilder
  def mount(params, %{event_stores: event_stores}, socket) do
    case event_stores_or_auto_discover(event_stores, socket.assigns.page.node) do
      {:ok, event_stores} ->
        socket = assign(socket, :event_stores, event_stores)
        mount_event_store(socket, nav_event_store(params, event_stores), event_stores)

      {:error, error} ->
        {:ok, assign(socket, event_store_ctx: nil, error: error)}
    end
  end

  defp mount_event_store(socket, nil, event_stores) do
    {module, _opts} = hd(event_stores)

    to =
      Params.to_live_dashboard_path(socket, socket.assigns.page, %Params{eventstore: module})

    {:ok, push_navigate(socket, to: to)}
  end

  defp mount_event_store(socket, event_store, _event_stores) do
    with :ok <- check_event_store(socket),
         {:ok, ctx} <- fetch_event_store_ctx(socket.assigns.page.node, event_store) do
      {:ok, assign(socket, event_store_ctx: ctx, error: nil)}
    else
      {:error, error} ->
        {:ok, assign(socket, event_store_ctx: nil, error: error)}
    end
  end

  defp fetch_event_store_ctx(node, event_store) do
    case Repo.fetch_conn(node, event_store) do
      {:ok, ctx} -> {:ok, ctx}
      _ -> {:error, :event_store_is_not_running}
    end
  end

  defp check_event_store(socket) do
    with :ok <- check_socket_connection(socket) do
      check_event_store_version(socket.assigns.page.node)
    end
  end

  @impl PageBuilder
  def handle_params(params, _url, socket) do
    params = Params.from_url(params)

    {:noreply,
     socket
     |> assign(:streams_page, params.streams_page || 1)
     |> assign(:events_page, params.events_page || 1)
     |> assign(:subscriptions_page, params.subscriptions_page || 1)
     |> assign(:snapshots_page, params.snapshots_page || 1)
     |> assign(:event_number, params.event)
     |> assign(:stream_uuid, params.stream)
     |> assign(:stream_modal_uuid, params.stream_modal)
     |> assign(:snapshot_uuid, params.snapshot_uuid)
     |> assign(:correlation_id, params.correlation_id)
     |> assign(:causation_id, params.causation_id)
     |> assign(:subscription_id, params.subscription_id)
     |> assign(:nav_tab, params.nav || "streams")}
  end

  @impl PageBuilder
  def handle_event("show_stream", %{"stream" => stream_uuid}, socket) do
    %{event_store_ctx: ctx, page: page} = socket.assigns

    to =
      Params.to_live_dashboard_path(socket, page, %Params{
        eventstore: ctx.event_store,
        stream_modal: stream_uuid
      })

    {:noreply, push_patch(socket, to: to)}
  end

  @impl PageBuilder
  def handle_event("show_event", %{"event" => event, "stream" => stream}, socket) do
    case Integer.parse(event) do
      {event_number, ""} ->
        %{event_store_ctx: ctx, page: page} = socket.assigns
        stream_uuid = if stream == "$all", do: nil, else: stream

        to =
          Params.to_live_dashboard_path(socket, page, %Params{
            eventstore: ctx.event_store,
            nav: "events",
            stream: stream_uuid,
            event: event_number
          })

        {:noreply, push_patch(socket, to: to)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl PageBuilder
  def handle_event("show_snapshot", %{"source" => source_uuid}, socket) do
    %{event_store_ctx: ctx, page: page} = socket.assigns

    to =
      Params.to_live_dashboard_path(socket, page, %Params{
        eventstore: ctx.event_store,
        nav: "snapshots",
        snapshot_uuid: source_uuid
      })

    {:noreply, push_patch(socket, to: to)}
  end

  @impl PageBuilder
  def handle_event("show_subscription", %{"subscription_id" => id}, socket) do
    %{event_store_ctx: ctx, page: page} = socket.assigns

    to =
      Params.to_live_dashboard_path(socket, page, %Params{
        eventstore: ctx.event_store,
        nav: "subscriptions",
        subscription_id: id
      })

    {:noreply, push_patch(socket, to: to)}
  end

  @impl PageBuilder
  def handle_event("show_correlation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: id_filter_path(socket, :correlation_id, id))}
  end

  @impl PageBuilder
  def handle_event("show_causation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: id_filter_path(socket, :causation_id, id))}
  end

  defp id_filter_path(socket, key, value) do
    %{event_store_ctx: ctx, page: page} = socket.assigns

    params = Map.put(%Params{eventstore: ctx.event_store, nav: "events"}, key, value)
    Params.to_live_dashboard_path(socket, page, params)
  end

  @impl PageBuilder
  def render(assigns) do
    if assigns[:error] do
      render_error(assigns)
    else
      ~H"""
      <div class="row">
        <div class="container">
          <ul class="nav nav-bar mt-n2 mb-4">
            <li :for={{module, _opts} <- @event_stores} class="nav-item">
              <.link
                patch={event_store_path(@socket, @page, module)}
                class={event_store_link_class(@event_store_ctx.event_store, module)}
              >
                {inspect(module)}
              </.link>
            </li>
          </ul>
        </div>
      </div>

      <div class="row">
        <div class="container">
          <ul class="nav nav-pills mt-n2 mb-4">
            <li class="nav-item">
              <.link
                patch={tab_path(@socket, @page, @event_store_ctx, "streams")}
                class={tab_link_class(@nav_tab, "streams")}
              >
                Streams
              </.link>
            </li>
            <li class="nav-item">
              <.link
                patch={tab_path(@socket, @page, @event_store_ctx, "events")}
                class={tab_link_class(@nav_tab, "events")}
              >
                Events
              </.link>
            </li>
            <li class="nav-item">
              <.link
                patch={tab_path(@socket, @page, @event_store_ctx, "subscriptions")}
                class={tab_link_class(@nav_tab, "subscriptions")}
              >
                Subscriptions
              </.link>
            </li>
            <li class="nav-item">
              <.link
                patch={tab_path(@socket, @page, @event_store_ctx, "snapshots")}
                class={tab_link_class(@nav_tab, "snapshots")}
              >
                Snapshots
              </.link>
            </li>
          </ul>
        </div>
      </div>

      <%= case @nav_tab do %>
        <% "streams" -> %>
          <StreamsTable.render
            ctx={@event_store_ctx}
            page={@page}
            socket={@socket}
            page_number={@streams_page}
          />
        <% "subscriptions" -> %>
          <.live_component
            module={SubscriptionsTable}
            id="subscriptions-table"
            ctx={@event_store_ctx}
            page={@page}
            page_number={@subscriptions_page}
            subscription_id={@subscription_id}
          />
        <% "snapshots" -> %>
          <.live_component
            module={SnapshotsTable}
            id="snapshots-table"
            ctx={@event_store_ctx}
            page={@page}
            page_number={@snapshots_page}
            snapshot_uuid={@snapshot_uuid}
          />
        <% _ -> %>
          <EventsTable.render
            ctx={@event_store_ctx}
            page={@page}
            socket={@socket}
            page_number={@events_page}
            event_number={@event_number}
            stream_uuid={@stream_uuid}
            correlation_id={@correlation_id}
            causation_id={@causation_id}
          />
      <% end %>

      <.live_modal
        :if={@stream_modal_uuid}
        id="stream-modal"
        title="Stream"
        return_to={stream_modal_return_to(@socket, @page)}
      >
        <StreamModal.render
          page={@page}
          ctx={@event_store_ctx}
          stream_uuid={@stream_modal_uuid}
          socket={@socket}
        />
      </.live_modal>
      """
    end
  end

  defp stream_modal_return_to(socket, page) do
    PageBuilder.live_dashboard_path(socket, page, stream_modal: nil)
  end

  defp event_store_path(socket, page, module) do
    Params.to_live_dashboard_path(socket, page, %Params{eventstore: module})
  end

  defp event_store_link_class({active, _opts}, module) when active == module,
    do: "nav-link active"

  defp event_store_link_class(_active, _module), do: "nav-link"

  defp tab_path(socket, page, %Context{} = ctx, tab) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      nav: tab
    })
  end

  defp tab_link_class(active, tab) when active == tab, do: "nav-link active"
  defp tab_link_class(_active, _tab), do: "nav-link"

  defp event_stores_or_auto_discover([], _node), do: {:error, :no_event_stores_available}
  defp event_stores_or_auto_discover(:auto_discover, node), do: auto_discover_event_stores(node)
  defp event_stores_or_auto_discover(config, _node) when is_list(config), do: normalize_event_stores(config)
  defp event_stores_or_auto_discover(_config, _node), do: {:error, :no_event_stores_available}

  defp normalize_event_stores(config) do
    {:ok, Enum.map(config, &normalize_event_store/1)}
  end

  defp normalize_event_store({event_store, opts}) when is_atom(event_store) and is_list(opts) do
    {event_store, opts}
  end

  defp normalize_event_store(event_store) when is_atom(event_store) do
    {event_store, name: event_store}
  end

  defp normalize_event_store(invalid) do
    raise ArgumentError, message: "Invalid event store config: " <> inspect(invalid)
  end

  defp auto_discover_event_stores(node) do
    with :ok <- check_event_store_version(node) do
      running_event_stores(node)
    end
  end

  defp running_event_stores(node) do
    case :rpc.call(node, EventStore, :all_instances, []) do
      [] ->
        {:error, :no_event_stores_available}

      event_stores when is_list(event_stores) ->
        {:ok, event_stores}

      {:badrpc, _error} ->
        {:error, :cannot_list_running_event_stores}
    end
  end

  defp nav_event_store(params, event_stores) do
    eventstore = Map.get(params, "eventstore")

    if eventstore && eventstore != "" do
      Enum.find(event_stores, fn {module, _opts} -> inspect(module) == eventstore end)
    end
  end

  defp check_socket_connection(socket) do
    if connected?(socket) do
      :ok
    else
      {:error, :connection_is_not_available}
    end
  end

  defp render_error(assigns) do
    error_message = error_message(assigns.error)
    assigns = assign(assigns, :error_message, error_message)

    ~H"""
    <.row>
      <:col>
        <.card>
          {@error_message}
        </.card>
      </:col>
    </.row>
    """
  end

  defp error_message(:connection_is_not_available),
    do: "Dashboard is not connected yet."

  defp error_message(:event_store_not_found),
    do: "This event store is not available for this node."

  defp error_message(:event_store_is_not_running),
    do: "This event store is not running on this node."

  defp error_message(:event_store_is_not_available),
    do: "EventStore is not available on remote node."

  defp error_message(:version_is_not_enough),
    do: "EventStore is outdated on remote node. Minimum version required is #{@minimum_event_store_version}"

  defp error_message(:no_event_stores_available),
    do: "There is no event store running on this node."

  defp error_message(:cannot_list_running_event_stores),
    do: "Could not list running event stores at remote node. Please try again later."

  defp error_message(:not_able_to_start_remotely),
    do: "Could not start the metrics server remotely. Please try again later."

  defp error_message({:badrpc, _}),
    do: "Could not send request to node. Try again later."

  defp check_event_store_version(node) do
    case :rpc.call(node, Application, :spec, [:eventstore, :vsn]) do
      {:badrpc, _reason} = error ->
        {:error, error}

      vsn when is_list(vsn) ->
        if Version.compare(to_string(vsn), @minimum_event_store_version) in [:gt, :eq] do
          :ok
        else
          {:error, :version_is_not_enough}
        end

      nil ->
        {:error, :event_store_is_not_available}
    end
  end
end
