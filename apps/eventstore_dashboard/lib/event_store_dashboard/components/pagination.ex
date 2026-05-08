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

  defp path_for(socket, page, param, page_number) do
    PageBuilder.live_dashboard_path(socket, page, [{param, page_number}])
  end
end
