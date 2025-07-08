defmodule Mix.Tasks.Trogon.TypeProvider.List do
  @moduledoc """
  Lists all registered type mappings for a given TypeProvider module.

  ## Usage

      mix trogon.type_provider.list TypeProvider

  ## Examples

      # List all types in a specific provider
      mix trogon.type_provider.list MyApp.EventTypeProvider
  """

  use Mix.Task

  @shortdoc "Lists registered type mappings for a TypeProvider"

  @impl Mix.Task
  def run(args) do
    case args do
      [module_name] ->
        list_types(module_name)

      [] ->
        Mix.shell().error("No TypeProvider module specified.")
        Mix.shell().info("")
        Mix.shell().info("Usage: mix trogon.type_provider.list MyApp.TypeProvider")

      _ ->
        Mix.shell().error("Too many arguments. Expected one module name.")
    end
  end

  defp to_elixir_module_name("Elixir." <> _rest = full_name) do
    String.to_atom(full_name)
  end

  defp to_elixir_module_name(module_name) do
    String.to_atom("Elixir.#{module_name}")
  end

  defp list_types(module_name) do
    try do
      module = to_elixir_module_name(module_name)

      # Try to ensure the module is loaded
      Code.ensure_loaded(module)

      case function_exported?(module, :__type_mapping__, 0) do
        true ->
          mappings = module.__type_mapping__()
          output_table(mappings, module_name)

        false ->
          Mix.shell().error("Module #{module_name} is not a TypeProvider or not compiled")
      end
    rescue
      ArgumentError ->
        # Check if it's really a non-existent module
        module = to_elixir_module_name(module_name)

        case Code.ensure_loaded(module) do
          {:error, :nofile} ->
            Mix.shell().error("Module #{module_name} does not exist")

          _ ->
            Mix.shell().error("Module #{module_name} is not a TypeProvider or not compiled")
        end

      error ->
        Mix.shell().error("Error loading module #{module_name}: #{Exception.message(error)}")
    end
  end

  defp output_table([], module_name) do
    Mix.shell().info("No type mappings found in #{module_name}")
  end

  defp output_table(mappings, module_name) do
    type_header = "Type Name"
    module_header = "Struct Module"

    type_width =
      mappings
      |> Enum.map(&type_length/1)
      |> Enum.max()
      |> max(String.length(type_header))

    module_width =
      mappings
      |> Enum.map(&module_length/1)
      |> Enum.max()
      |> max(String.length(module_header))

    header_line = [String.pad_trailing(type_header, type_width), " | ", module_header]
    separator_line = [String.duplicate("-", type_width), "-+-", String.duplicate("-", module_width)]

    data_lines =
      Enum.map(mappings, fn {_provider_mod, type, struct_mod} ->
        [String.pad_trailing(type, type_width), " | ", inspect(struct_mod)]
      end)

    total_line = "\nTotal: #{length(mappings)} type mappings"

    Mix.shell().info(
      IO.iodata_to_binary([
        "Type mappings for #{module_name}:\n",
        header_line,
        "\n",
        separator_line,
        "\n",
        Enum.intersperse(data_lines, "\n"),
        "\n",
        total_line
      ])
    )
  end

  defp module_length({_, _, mod}) do
    String.length(inspect(mod))
  end

  defp type_length({_, type, _}) do
    String.length(type)
  end
end
