defmodule OnePiece.Commanded do
  @moduledoc """
  Extend `Commanded` package. A swiss army knife for applications following Domain-Driven Design (DDD), Event Sourcing
  (ES), and Command and Query Responsibility Segregation (CQRS).
  """

  @doc """
  Deprecated, it has the same behavior as `OnePiece.Commanded.Helpers.cast_to/3`.
  """
  @spec cast_to(target :: map, params :: map, keys :: [Map.key()]) :: map
  @deprecated "Use `OnePiece.Commanded.Helpers.cast_to/3` instead."
  defdelegate cast_to(target, params, keys), to: OnePiece.Commanded.Helpers
end
