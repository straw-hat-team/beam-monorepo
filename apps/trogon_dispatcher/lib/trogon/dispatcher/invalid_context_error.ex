defmodule Trogon.Dispatcher.InvalidContextError do
  @moduledoc """
  Raised when a middleware returns something other than a valid `Trogon.Dispatcher.Context`.

  A middleware deals with one data type. It receives a context and it must return a context, whether it called `next`
  or halted. Returning the response directly is the common mistake and this error names the module that did it.

  The context it returns must also keep the context's invariants: `message`, `kind`, `dispatcher` and `registered_by`
  stay as the dispatch set them, and `assigns` and `private` stay maps. Checking them where the middleware hands the
  context back means a broken context fails naming the middleware that broke it, rather than wherever the next reader
  of that field happens to be.
  """

  @type reason :: :not_a_context | :changed | :not_a_map

  defexception [:module, :dispatched_message, :dispatcher, :returned, :field, reason: :not_a_context]

  @type t :: %__MODULE__{
          module: module(),
          dispatched_message: struct(),
          dispatcher: module(),
          returned: term(),
          field: atom() | nil,
          reason: reason()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      module: Keyword.get(opts, :module),
      dispatched_message: Keyword.get(opts, :dispatched_message),
      dispatcher: Keyword.get(opts, :dispatcher),
      returned: Keyword.get(opts, :returned),
      field: Keyword.get(opts, :field),
      reason: Keyword.get(opts, :reason, :not_a_context)
    }
  end

  @impl Exception
  def message(%__MODULE__{reason: :not_a_context} = exception) do
    """
    #{header(exception, "did not return a context")}

    Expected: a %Trogon.Dispatcher.Context{}
    Got: #{inspect(exception.returned)}

    A middleware takes a context and returns a context. To answer without calling the rest of the pipeline, put the
    response on the context instead of returning it:

        Trogon.Dispatcher.Context.put_response(context, {:error, :unauthorized})
    """
  end

  def message(%__MODULE__{reason: :changed} = exception) do
    """
    #{header(exception, "changed the context's #{inspect(exception.field)}")}

    Got: #{inspect(exception.returned)}

    #{inspect(exception.field)} is set by the dispatch and stays as it was for the whole pipeline.
    """
  end

  def message(%__MODULE__{reason: :not_a_map} = exception) do
    """
    #{header(exception, "returned a context whose #{inspect(exception.field)} is not a map")}

    Got: #{inspect(exception.returned)}
    """
  end

  defp header(exception, what) do
    "#{inspect(exception.module)} #{what} while dispatching " <>
      "#{inspect(exception.dispatched_message.__struct__)} in #{inspect(exception.dispatcher)}"
  end
end
