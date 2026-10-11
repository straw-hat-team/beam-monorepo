defmodule EventStoreDashboard.Stream do
  @moduledoc false

  @behaviour Access

  @type status :: :created | :deleted

  @type t :: %__MODULE__{
          stream_id: non_neg_integer() | nil,
          stream_uuid: String.t() | nil,
          stream_version: non_neg_integer() | nil,
          created_at: DateTime.t() | NaiveDateTime.t() | nil,
          deleted_at: DateTime.t() | NaiveDateTime.t() | nil,
          status: status() | nil
        }

  defstruct [
    :stream_id,
    :stream_uuid,
    :stream_version,
    :created_at,
    :deleted_at,
    :status
  ]

  @impl Access
  defdelegate fetch(struct, key), to: Map

  @impl Access
  defdelegate get_and_update(struct, key, fun), to: Map

  @impl Access
  defdelegate pop(struct, key), to: Map
end
