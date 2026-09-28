defmodule Trogon.Dispatcher.DispatchOptions do
  @moduledoc """
  Caller-supplied options for a dispatch.

  Everything a caller is allowed to seed the `Trogon.Dispatcher.Context` with lives here. `private` is deliberately
  absent: it is middleware scratch space, not caller input.
  """

  defstruct correlation_id: nil,
            causation_id: nil,
            actor: nil,
            assigns: %{}

  @type t :: %__MODULE__{
          correlation_id: term() | nil,
          causation_id: term() | nil,
          actor: term() | nil,
          assigns: map()
        }
end
