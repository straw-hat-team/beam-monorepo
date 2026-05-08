defmodule EventStoreDashboard.Event do
  @moduledoc false

  @behaviour Access

  @type t :: %__MODULE__{
          event_number: non_neg_integer() | nil,
          stream_version: non_neg_integer() | nil,
          event_id: String.t() | nil,
          stream_uuid: String.t() | nil,
          event_type: String.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          data: any(),
          metadata: any(),
          created_at: DateTime.t() | NaiveDateTime.t() | nil
        }

  defstruct [
    :event_number,
    :stream_version,
    :event_id,
    :stream_uuid,
    :event_type,
    :correlation_id,
    :causation_id,
    :data,
    :metadata,
    :created_at
  ]

  @impl Access
  defdelegate fetch(struct, key), to: Map

  @impl Access
  defdelegate get_and_update(struct, key, fun), to: Map

  @impl Access
  defdelegate pop(struct, key), to: Map
end
