defmodule Trogon.TypeProvider.UnregisteredMappingError do
  @moduledoc """
  Exception raised when attempting to access an unregistered type mapping in a TypeProvider.

  This exception provides detailed information about the failed lookup,
  including the mapping that was requested and the TypeProvider that was consulted.
  """

  defexception [:mapping, :type_provider]

  @type t :: %__MODULE__{
          mapping: term(),
          type_provider: module()
        }

  @impl Exception
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      mapping: Keyword.get(opts, :mapping),
      type_provider: Keyword.get(opts, :type_provider)
    }
  end

  @impl Exception
  def message(%__MODULE__{} = exception) do
    "Unregistered mapping for #{inspect(exception.mapping)} in #{inspect(exception.type_provider)}"
  end
end
