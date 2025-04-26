defmodule OnePiece.Commanded.TypeProvider.UnregisteredMappingError do
  defexception [:message, :mapping, :type_provider]

  @impl true
  def exception(opts) do
    %__MODULE__{
      message: "Unregistered mapping for #{inspect(opts[:mapping])} in #{inspect(opts[:type_provider])}",
      mapping: opts[:mapping],
      type_provider: opts[:type_provider]
    }
  end
end
