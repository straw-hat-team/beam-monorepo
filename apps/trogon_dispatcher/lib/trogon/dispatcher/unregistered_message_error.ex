defmodule Trogon.Dispatcher.UnregisteredMessageError do
  @moduledoc """
  Returned when a dispatcher is handed a message struct it does not know about.

  This is a value, not a raise: `dispatch_message/2` returns `{:error, %__MODULE__{}}` and only
  `dispatch_message!/2` turns it into an exception. A message that is not a struct at all is a different situation
  and raises `ArgumentError`, because routing matches on `__struct__` and an unregistered struct is a wiring state
  while a non-struct is a call-site bug.
  """

  defexception [:dispatched_message, :dispatcher]

  @type t :: %__MODULE__{
          dispatched_message: struct(),
          dispatcher: module()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Unregistered message #{inspect(message_module(exception.dispatched_message))} in #{inspect(exception.dispatcher)}

    To fix this, register the message in the dispatcher:

        defmodule #{inspect(exception.dispatcher)} do
          use Trogon.Dispatcher

          register_message #{inspect(message_module(exception.dispatched_message))}, kind: :command
        end

    Or import a dispatcher that already registers it:

        import_dispatcher SomeOther.Dispatcher
    """
  end

  defp message_module(message) when is_struct(message), do: message.__struct__
  defp message_module(message), do: message
end
