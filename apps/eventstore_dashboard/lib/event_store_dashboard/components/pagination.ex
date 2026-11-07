defmodule EventStoreDashboard.Components.Pagination do
  @moduledoc false

  use Phoenix.Component

  alias Phoenix.LiveDashboard.PageBuilder
  alias Phoenix.LiveView.Socket

  attr(:id, :string, required: true)
  attr(:param, :atom, required: true)
  attr(:page_number, :integer, required: true)
  attr(:total_pages, :integer, required: true)
  attr(:socket, Socket, required: true)
  attr(:page, PageBuilder, required: true)

  def render(assigns) do
    ~H"""
    <nav id={@id} class="d-flex justify-content-between align-items-center mb-4" aria-label="Pagination">
      <span class="text-muted small">
        Page {@page_number} of {max(@total_pages, 1)}
      </span>
      <div class="btn-group btn-group-sm" role="group">
        <.link
          :if={@page_number > 1}
          patch={path_for(@socket, @page, @param, @page_number - 1)}
          class="btn btn-secondary"
        >
          Previous
        </.link>
        <button :if={@page_number <= 1} class="btn btn-secondary" disabled>Previous</button>
        <.link
          :if={@page_number < @total_pages}
          patch={path_for(@socket, @page, @param, @page_number + 1)}
          class="btn btn-secondary"
        >
          Next
        </.link>
        <button :if={@page_number >= @total_pages} class="btn btn-secondary" disabled>Next</button>
      </div>
    </nav>
    """
  end

  @doc """
  Page count for a table that fetched `limit + 1` rows for `page_number`.

  `total_entries` may be a planner estimate, so it only sizes the page count.
  Whether a next page exists comes from the extra row, which keeps every row
  reachable even when the estimate is stale.
  """
  def total_pages(total_entries, limit, page_number, fetched_count) do
    estimated = if total_entries == 0, do: 0, else: div(total_entries - 1, limit) + 1

    cond do
      fetched_count > limit -> max(estimated, page_number + 1)
      fetched_count > 0 -> page_number
      true -> estimated
    end
  end

  defp path_for(socket, page, param, page_number) do
    PageBuilder.live_dashboard_path(socket, page, [{param, page_number}])
  end
end
