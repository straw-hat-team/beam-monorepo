defmodule Trogon.Dispatcher.DispatchError do
  @moduledoc """
  Raised by `dispatch_command!/2` when the dispatch returned `{:error, term}` and the term is not itself an exception.

  When the error term *is* an exception struct, `dispatch_command!/2` re-raises that exception instead, so the host's
  own error types survive the bang variant untouched.
  """

  defexception [:reason, :command, :dispatcher]

  @type t :: %__MODULE__{
          reason: term(),
          command: struct(),
          dispatcher: module()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      reason: Keyword.get(opts, :reason),
      command: Keyword.get(opts, :command),
      dispatcher: Keyword.get(opts, :dispatcher)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "Dispatch of #{inspect(command_module(exception.command))} in #{inspect(exception.dispatcher)} " <>
      "failed with #{inspect(exception.reason)}"
  end

  defp command_module(command) when is_struct(command), do: command.__struct__
  defp command_module(command), do: command
end
