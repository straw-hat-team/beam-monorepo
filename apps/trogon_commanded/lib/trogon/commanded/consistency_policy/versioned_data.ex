defmodule Trogon.Commanded.ConsistencyPolicy.VersionedData do
  @moduledoc """
  Wraps query result data with its version number.

  The version represents the projection's event stream version at the time
  of the read, indicating how up-to-date the data is.
  """

  @enforce_keys [:version, :data]
  defstruct [:version, :data]

  @typedoc "Event stream version at read time."
  @type version :: non_neg_integer()

  @typedoc "Wraps query result data with its projection version."
  @type t :: %__MODULE__{
          version: version(),
          data: term()
        }

  @spec new(version(), term()) :: t()
  def new(version, data) when is_integer(version) and version >= 0 do
    %__MODULE__{version: version, data: data}
  end
end
