defmodule Trogon.Dispatcher.DuplicateMessageError do
  @moduledoc """
  Raised at compile time when one message would resolve to two different pipelines in the same dispatcher.

  Reaching the same registration twice through a diamond of imports is fine and dedupes silently. This fires only when
  the two paths genuinely disagree: a different handler, a different kind, or a different effective middleware chain.
  """

  defexception [:dispatched_message, :dispatcher, :existing, :conflicting]

  @type registration :: %{
          dispatched_message: module(),
          handler: module(),
          kind: :command | :query,
          registered_by: module(),
          middleware: [{module(), term()}]
        }

  @type t :: %__MODULE__{
          dispatched_message: module(),
          dispatcher: module(),
          existing: registration(),
          conflicting: registration()
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
    A message may resolve to exactly one handler, one kind, and one middleware chain. Reaching the same registration
    twice through imports is fine; these two disagree.

    To fix this, register the message in exactly one place, or align the two dispatchers so the effective pipelines
    match.
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
