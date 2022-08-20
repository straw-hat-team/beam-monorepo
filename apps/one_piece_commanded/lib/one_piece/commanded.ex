defmodule OnePiece.Commanded do
  @moduledoc """
  Extend `Commanded` package. A swiss army knife for applications following Domain-Driven Design (DDD), Event Sourcing
  (ES), and Command and Query Responsibility Segregation (CQRS).
  """

  defdelegate cast_to(target, params, keys), to: OnePiece.Commanded.Helpers
  defdelegate skip_or_retry(tuple_response, context), to: OnePiece.Commanded.Helpers
  defdelegate skip_or_retry(tuple_response, delay, context), to: OnePiece.Commanded.Helpers
end
