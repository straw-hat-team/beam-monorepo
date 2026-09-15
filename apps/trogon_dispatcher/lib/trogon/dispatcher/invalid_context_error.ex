defmodule Trogon.Dispatcher.InvalidContextError do
  @moduledoc """
  Raised when a middleware returns something other than a `Trogon.Dispatcher.Context`.

  A middleware deals with one data type. It receives a context and it must return a context, whether it called `next`
  or halted. Returning the response directly is the common mistake and this error names the module that did it.
  """

  defexception [:module, :dispatched_message, :dispatcher, :returned]

  @type t :: %__MODULE__{
          module: module(),
          dispatched_message: struct(),
          dispatcher: module(),
          returned: term()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      module: Keyword.get(opts, :module),
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher),
      returned: Keyword.get(opts, :returned)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    #{inspect(exception.module)} did not return a context while dispatching \
    #{inspect(message_module(exception.dispatched_message))} in #{inspect(exception.dispatcher)}

    Expected: a %Trogon.Dispatcher.Context{}
    Got: #{inspect(exception.returned)}

    A middleware takes a context and returns a context. To answer without calling the rest of the pipeline, put the
    response on the context instead of returning it:

        Trogon.Dispatcher.Context.put_response(context, {:error, :unauthorized})
    """
  end

  defp message_module(message) when is_struct(message), do: message.__struct__
  defp message_module(message), do: message
end
