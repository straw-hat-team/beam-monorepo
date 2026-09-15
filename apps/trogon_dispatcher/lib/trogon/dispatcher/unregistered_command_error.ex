defmodule Trogon.Dispatcher.UnregisteredCommandError do
  @moduledoc """
  Returned when a dispatcher is handed a command struct it does not know about.

  This is a value, not a raise: `dispatch_command/2` is total and returns `{:error, %__MODULE__{}}`. Only
  `dispatch_command!/2` turns it into an exception.
  """

  defexception [:command, :dispatcher]

  @type t :: %__MODULE__{
          command: struct(),
          dispatcher: module()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      command: Keyword.get(opts, :command),
      dispatcher: Keyword.get(opts, :dispatcher)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Unregistered command #{inspect(command_module(exception.command))} in #{inspect(exception.dispatcher)}

    To fix this, register the command in the dispatcher:

        defmodule #{inspect(exception.dispatcher)} do
          use Trogon.Dispatcher

          register_command #{inspect(command_module(exception.command))}, kind: :command
        end

    Or import a dispatcher that already registers it:

        import_dispatcher SomeOther.Dispatcher
    """
  end

  defp command_module(command) when is_struct(command), do: command.__struct__
  defp command_module(command), do: command
end
