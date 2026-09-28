defmodule Trogon.Dispatcher.DuplicateMessageError do
  @moduledoc """
  Raised at compile time when one message would resolve to two different pipelines in the same dispatcher.

  Reaching the same registration twice through a diamond of imports is fine and dedupes silently. This fires only when
  the two paths genuinely disagree: a different handler, a different kind, a different effective middleware chain, or
  a different dispatcher that registered the message. Two dispatchers registering the same message conflict even when
  their pipelines match, because a message has one owning boundary and `registered_by` reports it.
  """

  defexception [:dispatched_message, :dispatcher, :existing, :conflicting]

  @type t :: %__MODULE__{
          dispatched_message: module(),
          dispatcher: module(),
          existing: Trogon.Dispatcher.registration(),
          conflicting: Trogon.Dispatcher.registration()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher),
      existing: Keyword.get(opts, :existing),
      conflicting: Keyword.get(opts, :conflicting)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Conflicting registration for #{inspect(exception.dispatched_message)} in #{inspect(exception.dispatcher)}

    Already registered:
    #{describe(exception.existing)}
    Conflicting registration:
    #{describe(exception.conflicting)}
    A message may resolve to exactly one handler, one kind, one middleware chain, and one registering dispatcher.
    Reaching the same registration twice through imports is fine; these two disagree.

    To fix this, register the message in exactly one dispatcher. If both registrations come from that one dispatcher,
    align the paths that import it so the effective middleware chains match.
    """
  end

  defp describe(%{} = registration) do
    """
      handler: #{inspect(registration.handler)}
      kind: #{inspect(registration.kind)}
      registered by: #{inspect(registration.registered_by)}
      middleware: #{inspect(Enum.map(registration.middleware, &elem(&1, 0)))}
    """
  end

  defp describe(other), do: "  #{inspect(other)}\n"
end
