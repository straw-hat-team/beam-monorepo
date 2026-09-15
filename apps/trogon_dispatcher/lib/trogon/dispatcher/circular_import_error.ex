defmodule Trogon.Dispatcher.CircularImportError do
  @moduledoc """
  Raised at compile time when `import_dispatcher` would close a cycle.

  A cycle between two separately compiled dispatchers usually shows up as a compiler deadlock before this runs. The
  check exists so the cases it can catch produce a legible message instead.
  """

  defexception [:dispatcher, :imported, :path]

  @type t :: %__MODULE__{
          dispatcher: module(),
          imported: module(),
          path: [module()]
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      dispatcher: Keyword.get(opts, :dispatcher),
      imported: Keyword.get(opts, :imported),
      path: Keyword.get(opts, :path, [])
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    """
    Circular import in #{inspect(exception.dispatcher)}

    Importing #{inspect(exception.imported)} would close this cycle:

        #{Enum.map_join(exception.path, " -> ", &inspect/1)}

    Dispatchers compose as an acyclic graph, so a diamond is fine and only a cycle is not. Extract the shared
    registrations into a dispatcher that both sides import.
    """
  end
end
