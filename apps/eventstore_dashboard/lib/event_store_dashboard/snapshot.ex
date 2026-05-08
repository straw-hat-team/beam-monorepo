defmodule EventStoreDashboard.Snapshot do
  @moduledoc false

  defstruct [
    :source_uuid,
    :source_version,
    :source_type,
    :data,
    :metadata,
    :created_at
  ]
end
