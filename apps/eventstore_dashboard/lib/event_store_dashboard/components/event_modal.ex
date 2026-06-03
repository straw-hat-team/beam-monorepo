defmodule EventStoreDashboard.Components.EventModal do
  @moduledoc false

  use Phoenix.LiveComponent

  alias EventStoreDashboard.Components.DataField
  alias EventStoreDashboard.Params
  alias EventStoreDashboard.Repo
  alias EventStoreDashboard.Repo.Context
  alias Phoenix.LiveDashboard.PageBuilder

  @inspect_opts [limit: :infinity, printable_limit: :infinity, pretty: true]

  @impl true
  def update(assigns, socket) do
    {:ok, assign_event(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div :if={@error} class="alert alert-danger" role="alert">
        {@error}
      </div>
      <div :if={is_nil(@error)} class="tabular-info">
        <table class="table table-hover tabular-info-table">
          <tbody>
            <tr>
              <td class="border-top-0">Id</td>
              <td class="border-top-0"><pre>{@event.event_id}</pre></td>
            </tr>
            <tr>
              <td>Stream</td>
              <td>
                <.link
                  patch={stream_modal_path(@socket, @page, @ctx, @event.stream_uuid)}
                  class="es-modal-trigger"
                >
                  {@event.stream_uuid}
                </.link>
              </td>
            </tr>
            <tr :if={@stream_uuid == "$all"}>
              <td>Position</td>
              <td><pre>{@event.event_number}</pre></td>
            </tr>
            <tr>
              <td>Stream Version</td>
              <td><pre>@{@event.stream_version}</pre></td>
            </tr>
            <tr>
              <td>Type</td>
              <td><pre>{@event.event_type}</pre></td>
            </tr>
            <tr>
              <td>Causation ID</td>
              <td>
                <div :if={@event.causation_id} class="d-flex align-items-baseline">
                  <.link
                    patch={id_filter_path(@socket, @page, @ctx, :causation_id, @event.causation_id)}
                    phx-page-loading
                  >
                    {@event.causation_id}
                  </.link>
                  <span :if={@causation_count} class="badge badge-secondary ml-2">
                    {count_label(@causation_count)}
                  </span>
                </div>
                <pre :if={is_nil(@event.causation_id)} class="mb-0"></pre>
              </td>
            </tr>
            <tr>
              <td>Correlation ID</td>
              <td>
                <div :if={@event.correlation_id} class="d-flex align-items-baseline">
                  <.link
                    patch={id_filter_path(@socket, @page, @ctx, :correlation_id, @event.correlation_id)}
                    phx-page-loading
                  >
                    {@event.correlation_id}
                  </.link>
                  <span :if={@correlation_count} class="badge badge-secondary ml-2">
                    {count_label(@correlation_count)}
                  </span>
                </div>
                <pre :if={is_nil(@event.correlation_id)} class="mb-0"></pre>
              </td>
            </tr>
            <tr>
              <td>Created at</td>
              <td><pre>{@event.created_at}</pre></td>
            </tr>
            <DataField.row label="Data" value={@event.data} inspect_opts={@inspect_opts} />
            <DataField.row label="Metadata" value={@event.metadata} inspect_opts={@inspect_opts} />
          </tbody>
        </table>
      </div>

      <div class="modal-footer d-flex justify-content-between align-items-center">
        <span class="text-muted small">
          {position_label(@stream_uuid, @event_number, @stream_version)}
        </span>
        <div class="btn-group btn-group-sm" role="group">
          <.link
            :if={@can_prev}
            patch={paginate_path(@socket, @page, @event_number - 1)}
            class="btn btn-outline-secondary"
          >
            &larr; Previous
          </.link>
          <button :if={not @can_prev} class="btn btn-outline-secondary" disabled>&larr; Previous</button>
          <.link
            :if={@can_next}
            patch={paginate_path(@socket, @page, @event_number + 1)}
            class="btn btn-outline-secondary"
          >
            Next &rarr;
          </.link>
          <button :if={not @can_next} class="btn btn-outline-secondary" disabled>Next &rarr;</button>
        </div>
      </div>
    </div>
    """
  end

  defp stream_modal_path(socket, page, %Context{} = ctx, stream_uuid) do
    Params.to_live_dashboard_path(socket, page, %Params{
      eventstore: ctx.event_store,
      stream_modal: stream_uuid,
      event: nil
    })
  end

  defp id_filter_path(socket, page, %Context{} = ctx, key, value) do
    params = Map.put(%Params{eventstore: ctx.event_store, nav: "events"}, key, value)
    Params.to_live_dashboard_path(socket, page, params)
  end

  defp paginate_path(socket, page, event_number) do
    PageBuilder.live_dashboard_path(socket, page, event: event_number)
  end

  defp assign_event(socket, assigns, read_stream_direction \\ :forward) do
    %{
      page: page,
      ctx: ctx,
      event_number: event_number,
      return_to: return_to,
      stream_uuid: stream_uuid
    } = assigns

    stream = fetch_stream(page.node, ctx, stream_uuid)
    stream_version = stream && stream.stream_version

    base = [
      page: page,
      ctx: ctx,
      stream_uuid: stream_uuid,
      return_to: return_to,
      inspect_opts: @inspect_opts,
      stream_version: stream_version
    ]

    case read_event(page.node, ctx, stream, read_stream_direction, event_number) do
      {:ok, event} ->
        {correlation_count, causation_count} = fetch_id_counts(page.node, ctx, event)

        assign(
          socket,
          base ++
            [
              event_number: event.event_number,
              event: event,
              error: nil,
              correlation_count: correlation_count,
              causation_count: causation_count,
              can_prev: event.event_number > 1,
              can_next: can_go_next?(event.event_number, stream_version)
            ]
        )

      {:error, reason} ->
        {error, can_prev, can_next} = error_state(reason, event_number, stream_version)

        assign(
          socket,
          base ++
            [
              event_number: event_number,
              event: nil,
              error: error,
              correlation_count: nil,
              causation_count: nil,
              can_prev: can_prev,
              can_next: can_next
            ]
        )
    end
  end

  defp error_state(:event_not_found, event_number, stream_version),
    do: {"Event not found", event_number > 1, can_go_next?(event_number, stream_version)}

  defp fetch_stream(_node, nil, _stream_uuid), do: nil

  defp fetch_stream(node, %Context{} = ctx, stream_uuid) do
    case Repo.fetch_stream(node, ctx, stream_uuid) do
      {:ok, stream} -> stream
      _ -> nil
    end
  end

  defp fetch_id_counts(node, %Context{} = ctx, event) do
    {count_for(node, ctx, :correlation_id, event.correlation_id),
     count_for(node, ctx, :causation_id, event.causation_id)}
  end

  defp count_for(_node, _ctx, _column, nil), do: nil

  defp count_for(node, %Context{} = ctx, column, value) do
    case Repo.count_events_by_id(node, ctx, column, value) do
      {:ok, count} -> count
      _ -> nil
    end
  end

  defp read_event(_node, _ctx, nil, _direction, _event_number), do: {:error, :event_not_found}

  defp read_event(node, %Context{} = ctx, stream, _direction, event_number) do
    case Repo.query_event_at_version(node, ctx, stream.stream_id, event_number) do
      {:ok, row} -> {:ok, Repo.row_to_event(row, ctx)}
      {:error, _} = error -> error
      _ -> {:error, :event_not_found}
    end
  end

  defp can_go_next?(_event_number, nil), do: false
  defp can_go_next?(event_number, stream_version), do: event_number < stream_version

  defp count_label(1), do: "1 event"
  defp count_label(n), do: "#{n} events"

  defp position_label("$all", event_number, nil), do: "Position #{event_number}"
  defp position_label("$all", event_number, total), do: "Position #{event_number} of #{total}"
  defp position_label(_stream_uuid, event_number, nil), do: "Stream Version #{event_number}"
  defp position_label(_stream_uuid, event_number, total), do: "Stream Version #{event_number} of #{total}"
end
