defmodule Trogon.Credo.ModuleDeclaration do
  @moduledoc false

  alias Trogon.Credo.ModuleName

  defstruct [:namespace, :parts, :meta]

  # The `defmodule` declarations of a source file, in source order. `namespace`
  # holds the fully qualified parts, `parts` the ones written in the `defmodule`.
  # A nested `defmodule` extends the namespace of the enclosing one.
  #
  # Given a non empty `using:`, only the declarations that `use` one of those
  # modules are kept, with the `use` resolved through the file's aliases.
  #
  # Code inside a `quote` block is skipped, since a module declared there, or a
  # `use` written there, belongs to wherever the macro expands.
  def collect_module_declarations(source_file, opts) do
    for_use = opts |> Keyword.get(:using, []) |> Enum.map(&ModuleName.full/1)
    aliases = ModuleName.collect_aliases(source_file)
    {modules, uses} = Credo.Code.prewalk(source_file, &traverse(&1, &2, aliases), {[], []})

    modules
    |> Enum.reverse()
    |> Enum.filter(&applies_to?(&1, uses, for_use))
  end

  defp traverse({:defmodule, _meta, [{:__aliases__, meta, parts} | rest]}, acc, aliases) do
    {[], walk(rest, parts, put_module(acc, parts, parts, meta), aliases)}
  end

  defp traverse({:defmodule, _meta, [name | rest]}, acc, aliases) do
    {[], walk(rest, [name], acc, aliases)}
  end

  defp traverse({:quote, _meta, _args}, acc, _aliases), do: {[], acc}

  defp traverse(ast, acc, _aliases), do: {ast, acc}

  # Manual recursion (mirroring `traverse/3` above) so that a nested
  # `defmodule` extends the namespace of the enclosing one and a `use` site is
  # attributed to its enclosing module's fully qualified name.
  defp walk({:defmodule, _meta, [{:__aliases__, meta, parts} | rest]}, namespace, acc, aliases) do
    full_namespace = namespace ++ parts

    walk(rest, full_namespace, put_module(acc, full_namespace, parts, meta), aliases)
  end

  defp walk({:defmodule, _meta, [name | rest]}, _namespace, acc, aliases) do
    walk(rest, [name], acc, aliases)
  end

  defp walk({:use, _meta, [{:__aliases__, _, used_parts} | _]}, namespace, {modules, uses}, aliases) do
    {modules, [{namespace, ModuleName.resolve(used_parts, aliases)} | uses]}
  end

  defp walk({:quote, _meta, _args}, _namespace, acc, _aliases), do: acc

  defp walk({_, _, args}, namespace, acc, aliases) when is_list(args) do
    walk(args, namespace, acc, aliases)
  end

  defp walk({left, right}, namespace, acc, aliases) do
    walk(right, namespace, walk(left, namespace, acc, aliases), aliases)
  end

  defp walk(list, namespace, acc, aliases) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, namespace, &2, aliases))
  end

  defp walk(_ast, _namespace, acc, _aliases), do: acc

  defp put_module({modules, uses}, namespace, parts, meta) do
    {[%__MODULE__{namespace: namespace, parts: parts, meta: meta} | modules], uses}
  end

  defp applies_to?(_module, _uses, []), do: true

  defp applies_to?(module, uses, for_use) do
    Enum.any?(uses, &uses?(&1, module, for_use))
  end

  defp uses?({namespace, used}, %__MODULE__{} = module, for_use) do
    namespace == module.namespace and used in for_use
  end
end
