defmodule Trogon.Dispatcher.DispatchError do
  @moduledoc """
  Raised by `dispatch_message!/2` when the dispatch returned `{:error, term}` and the term is not itself an exception.

  When the error term *is* an exception struct, `dispatch_message!/2` re-raises that exception instead, so the host's
  own error types survive the bang variant untouched.
  """

  defexception [:reason, :dispatched_message, :dispatcher]

  @type t :: %__MODULE__{
          reason: term(),
          dispatched_message: struct(),
          dispatcher: module()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      reason: Keyword.get(opts, :reason),
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "Dispatch of #{inspect(message_module(exception.dispatched_message))} in #{inspect(exception.dispatcher)} " <>
      "failed with #{inspect(exception.reason)}"
  end

  defp message_module(message) when is_struct(message), do: message.__struct__
  defp message_module(message), do: message
end
