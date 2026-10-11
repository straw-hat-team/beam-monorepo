defmodule Trogon.Commanded do
  @moduledoc """
  Extend `Commanded` package. A swiss army knife for applications following Domain-Driven Design (DDD), Event Sourcing
  (ES), and Command and Query Responsibility Segregation (CQRS).
  """

  defdelegate cast_to(target, params, keys), to: Trogon.Commanded.Helpers
  defdelegate skip_or_retry(tuple_response, context), to: Trogon.Commanded.Helpers
  defdelegate tracing_from_metadata(metadata), to: Trogon.Commanded.Helpers
  defdelegate tracing_from_metadata(opts, metadata), to: Trogon.Commanded.Helpers
  defdelegate skip_or_retry(tuple_response, delay, context), to: Trogon.Commanded.Helpers
  defdelegate increase_failure_counter(failure_context), to: Trogon.Commanded.Helpers
  defdelegate ignore_error(result, error), to: Trogon.Commanded.Helpers
end
