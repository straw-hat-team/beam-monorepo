defmodule EventStoreDashboard.Params do
  @moduledoc false

  alias Phoenix.LiveDashboard.PageBuilder

  defstruct [
    :eventstore,
    :nav,
    :stream,
    :stream_modal,
    :event,
    :streams_page,
    :events_page,
    :subscriptions_page,
    :snapshots_page,
    :subscription_id,
    :snapshot_uuid,
    :correlation_id,
    :causation_id,
    :event_type
  ]

  @type t :: %__MODULE__{
          eventstore: String.t() | module() | {module(), keyword()} | nil,
          nav: String.t() | nil,
          stream: String.t() | nil,
          stream_modal: String.t() | nil,
          event: integer() | nil,
          streams_page: pos_integer() | nil,
          events_page: pos_integer() | nil,
          subscriptions_page: pos_integer() | nil,
          snapshots_page: pos_integer() | nil,
          subscription_id: integer() | nil,
          snapshot_uuid: String.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          event_type: String.t() | nil
        }

  @nav_tabs ~w(streams events subscriptions snapshots)

  @spec from_url(map()) :: t()
  def from_url(params) when is_map(params) do
    %__MODULE__{
      eventstore: parse_string(params, "eventstore"),
      nav: parse_nav(params),
      stream: parse_stream(params),
      stream_modal: parse_string(params, "stream_modal"),
      event: parse_integer(params, "event"),
      streams_page: parse_page(params, "streams_page"),
      events_page: parse_page(params, "events_page"),
      subscriptions_page: parse_page(params, "subscriptions_page"),
      snapshots_page: parse_page(params, "snapshots_page"),
      subscription_id: parse_integer(params, "subscription_id"),
      snapshot_uuid: parse_string(params, "snapshot_uuid"),
      correlation_id: parse_string(params, "correlation_id"),
      causation_id: parse_string(params, "causation_id"),
      event_type: parse_string(params, "event_type")
    }
  end

  @spec to_live_dashboard_path(Phoenix.LiveView.Socket.t(), map(), t()) :: String.t()
  def to_live_dashboard_path(socket, page, %__MODULE__{} = params) do
    keyword =
      params
      |> Map.from_struct()
      |> Map.update!(:eventstore, &eventstore_param/1)
      |> Enum.to_list()

    PageBuilder.live_dashboard_path(socket, page, keyword)
  end

  @spec eventstore_param(String.t() | module() | {module(), keyword()} | nil) :: String.t() | nil
  def eventstore_param(nil), do: nil
  def eventstore_param({module, _opts}) when is_atom(module), do: inspect(module)
  def eventstore_param(module) when is_atom(module), do: inspect(module)
  def eventstore_param(value) when is_binary(value), do: value

  defp parse_string(params, key), do: string(Map.get(params, key))

  defp string(""), do: nil
  defp string(value) when is_binary(value), do: value
  defp string(_), do: nil

  defp parse_integer(params, key), do: integer(Map.get(params, key))

  defp integer(value) when is_binary(value), do: integer_parsed(Integer.parse(value))
  defp integer(_), do: nil

  defp integer_parsed({n, ""}), do: n
  defp integer_parsed(_), do: nil

  defp parse_page(params, key), do: page(parse_integer(params, key))

  defp page(n) when is_integer(n) and n >= 1, do: n
  defp page(_), do: nil

  defp parse_nav(%{"nav" => value}) when value in @nav_tabs, do: value
  defp parse_nav(_), do: nil

  defp parse_stream(%{"stream" => ""}), do: "$all"
  defp parse_stream(%{"stream" => value}) when is_binary(value), do: value
  defp parse_stream(_), do: "$all"
end
