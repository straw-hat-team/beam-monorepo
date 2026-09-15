defmodule Trogon.Dispatcher.InvalidResponseError do
  @moduledoc """
  Raised when a handler or a middleware returns something outside the response contract.

  This is a contract violation by code in your own application, not a runtime failure mode, which is why it raises
  rather than returning `{:error, term}`. It is the same call Plug makes when a plug fails to return a `Plug.Conn`.

  Note in particular that a bare list is invalid. A collection-returning query wraps its results in a struct you
  define; the library has no pagination model of its own.

  A middleware that halts without putting a response on the context lands here too, with a `nil` response.
  """

  defexception [:module, :dispatched_message, :dispatcher, :response]

  @type t :: %__MODULE__{
          module: module(),
          dispatched_message: struct(),
          dispatcher: module(),
          response: term()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      module: Keyword.get(opts, :module),
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher),
      response: Keyword.get(opts, :response)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Invalid response from #{inspect(exception.module)} while dispatching \
    #{inspect(message_module(exception.dispatched_message))} in #{inspect(exception.dispatcher)}

    Expected: :ok, {:ok, struct} or {:error, term}
    Got: #{inspect(exception.response)}
    #{hint(exception.response)}
    """
  end

  defp hint(nil) do
    """

    A middleware that does not call `next` must put its own response on the context before returning it:

        Trogon.Dispatcher.Context.put_response(context, {:error, :unauthorized})
    """
  end

  defp hint(_response) do
    """

    The success value must be a struct. A map, a keyword list, a bare list, or a native value will not do. Wrap
    collections in a struct you define:

        {:ok, %MyApp.UserPage{items: users, cursor: cursor}}
    """
  end

  defp message_module(message) when is_struct(message), do: message.__struct__
  defp message_module(message), do: message
end
