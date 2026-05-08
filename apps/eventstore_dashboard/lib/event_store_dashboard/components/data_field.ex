defmodule EventStoreDashboard.Components.DataField do
  @moduledoc false

  use Phoenix.Component

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)
  attr(:inspect_opts, :list, required: true)

  def row(%{value: {:deserialization_error, exception, raw}} = assigns) do
    assigns = assign(assigns, exception: exception, raw: raw)

    ~H"""
    <tr>
      <td>
        <div class="d-flex align-items-center">
          <span>{@label}</span>
          <span class="badge badge-danger ml-2" title={Exception.message(@exception)}>
            Failed
          </span>
        </div>
      </td>
      <td><pre>{inspect(@raw, @inspect_opts)}</pre></td>
    </tr>
    """
  end

  def row(assigns) do
    ~H"""
    <tr>
      <td>{@label}</td>
      <td><pre>{inspect(@value, @inspect_opts)}</pre></td>
    </tr>
    """
  end
end
