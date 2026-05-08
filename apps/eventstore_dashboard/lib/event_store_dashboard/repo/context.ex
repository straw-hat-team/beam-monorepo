defmodule EventStoreDashboard.Repo.Context do
  @moduledoc false

  @type t :: %__MODULE__{
          event_store: {module(), keyword()},
          conn: atom() | pid(),
          schema: String.t(),
          serializer: module() | nil
        }

  @enforce_keys [:event_store, :conn, :schema]
  defstruct [:event_store, :conn, :schema, :serializer]
end
