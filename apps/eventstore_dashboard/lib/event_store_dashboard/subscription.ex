defmodule EventStoreDashboard.Subscription do
  @moduledoc false

  @behaviour Access

  @type t :: %__MODULE__{
          subscription_id: integer() | nil,
          stream_uuid: String.t() | nil,
          subscription_name: String.t() | nil,
          last_seen: non_neg_integer() | nil,
          stream_version: non_neg_integer(),
          lag: non_neg_integer(),
          created_at: DateTime.t() | NaiveDateTime.t() | nil,
          trend: :catching_up | :falling_behind | :stable | :unknown
        }

  defstruct [
    :subscription_id,
    :stream_uuid,
    :subscription_name,
    :last_seen,
    :created_at,
    stream_version: 0,
    lag: 0,
    trend: :unknown
  ]

  @impl Access
  defdelegate fetch(struct, key), to: Map

  @impl Access
  defdelegate get_and_update(struct, key, fun), to: Map

  @impl Access
  defdelegate pop(struct, key), to: Map
end
