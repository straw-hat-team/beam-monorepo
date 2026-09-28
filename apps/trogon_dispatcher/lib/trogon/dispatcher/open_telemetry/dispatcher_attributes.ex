defmodule Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes do
  @moduledoc """
  OpenTelemetry span attribute names that `Trogon.Dispatcher.OpenTelemetry` sets beyond the semantic conventions.

  Library attributes are prefixed with `trogon_dispatcher.` so they never collide with standard OpenTelemetry
  attributes, and use `snake_case` with dot notation for namespacing.

  | Attribute | Type | Description |
  |---|---|---|
  | `trogon_dispatcher.message` | string | The dispatched message module |
  | `trogon_dispatcher.kind` | string | `command` or `query` |
  | `trogon_dispatcher.dispatcher` | string | The dispatcher whose `dispatch_message/2` was called |
  | `trogon_dispatcher.registered_by` | string | The dispatcher that declared the registration |
  | `trogon_dispatcher.correlation_id` | string | Correlation ID for tracing related operations |
  | `trogon_dispatcher.causation_id` | string | Causation ID linking cause and effect |
  | `erlang.exception.kind` | atom | `:error`, `:throw` or `:exit` for a pipeline that raised, threw or exited |

  ## Example

      iex> Trogon.Dispatcher.OpenTelemetry.DispatcherAttributes.trogon_dispatcher_message()
      :"trogon_dispatcher.message"
  """

  @doc """
  The dispatched message module.
  """
  @spec trogon_dispatcher_message() :: :"trogon_dispatcher.message"
  def trogon_dispatcher_message, do: :"trogon_dispatcher.message"

  @doc """
  Whether the message is a command or a query.
  """
  @spec trogon_dispatcher_kind() :: :"trogon_dispatcher.kind"
  def trogon_dispatcher_kind, do: :"trogon_dispatcher.kind"

  @doc """
  The dispatcher whose `dispatch_message/2` was called.
  """
  @spec trogon_dispatcher_dispatcher() :: :"trogon_dispatcher.dispatcher"
  def trogon_dispatcher_dispatcher, do: :"trogon_dispatcher.dispatcher"

  @doc """
  The dispatcher that declared the registration.
  """
  @spec trogon_dispatcher_registered_by() :: :"trogon_dispatcher.registered_by"
  def trogon_dispatcher_registered_by, do: :"trogon_dispatcher.registered_by"

  @doc """
  The correlation ID for tracing related operations.
  """
  @spec trogon_dispatcher_correlation_id() :: :"trogon_dispatcher.correlation_id"
  def trogon_dispatcher_correlation_id, do: :"trogon_dispatcher.correlation_id"

  @doc """
  The causation ID linking cause and effect.
  """
  @spec trogon_dispatcher_causation_id() :: :"trogon_dispatcher.causation_id"
  def trogon_dispatcher_causation_id, do: :"trogon_dispatcher.causation_id"

  @doc """
  The Erlang exception class of a pipeline that raised, threw or exited.

  OpenTelemetry has no semantic convention for it yet.
  """
  @spec erlang_exception_kind() :: :"erlang.exception.kind"
  def erlang_exception_kind, do: :"erlang.exception.kind"
end
