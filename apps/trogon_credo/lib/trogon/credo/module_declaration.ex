defmodule Trogon.Credo.ModuleDeclaration do
  @moduledoc false

  alias Credo.SourceFile
  alias Trogon.Credo.ModuleName

  defstruct [:namespace, :parts, :meta]

  # The `defmodule` declarations of a source file, in source order. `namespace`
  # holds the fully qualified parts, `parts` the ones written in the `defmodule`.
  # A nested `defmodule` extends the namespace of the enclosing one.
  #
  # Given a non empty `using:`, only the declarations that `use` one of those
  # modules are kept, with the `use` resolved through the aliases in effect where
  # it is written, so an alias in a sibling module does not change what it names.
  #
  # Code inside a `quote` block is skipped, since a module declared there, or a
  # `use` written there, belongs to wherever the macro expands.
  def collect_module_declarations(source_file, opts) do
    for_use = opts |> Keyword.get(:using, []) |> Enum.map(&ModuleName.full/1)
    {{modules, uses}, _aliases} = source_file |> SourceFile.ast() |> walk([], %{}, {[], []})

    modules
    |> Enum.reverse()
    |> Enum.filter(&applies_to?(&1, uses, for_use))
  end

  # The fully qualified name of a file's outermost module, read from its first
  # `defmodule`, nested ones left out. `nil` when the file has no `defmodule`,
  # or when that outermost one is not written as an alias, `__MODULE__.Child`
  # for instance, since what it names is only known at compile time.
  #
  # Code inside a `quote` block is skipped, since a module declared there
  # belongs to wherever the macro expands rather than to the file that writes
  # it.
  def outermost_module_name(source_file) do
    source_file
    |> Credo.Code.prewalk(&outermost/2, {false, nil})
    |> elem(1)
  end

  defp outermost({:quote, _meta, _args}, acc), do: {[], acc}

  defp outermost({:defmodule, _meta, _args}, {true, name}), do: {[], {true, name}}

  defp outermost({:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _]}, {false, _name}) do
    {[], {true, readable_name(parts)}}
  end

  defp outermost({:defmodule, _meta, _args}, {false, _name}), do: {[], {true, nil}}

  defp outermost(ast, acc), do: {ast, acc}

  defp readable_name(parts) do
    if Enum.all?(parts, &is_atom/1) do
      ModuleName.full(parts)
    else
      nil
    end
  end

  # Returns the accumulator along with the aliases in effect after the node, so
  # an `alias` reaches the expressions after it in the same block and nothing
  # outside of it, the way Elixir scopes one lexically.
  defp walk({:defmodule, _meta, [{:__aliases__, meta, parts} | rest]}, namespace, aliases, acc) do
    full_namespace = namespace ++ parts
    {acc, _aliases} = walk(rest, full_namespace, aliases, put_module(acc, full_namespace, parts, meta))
    {acc, aliases}
  end

  defp walk({:defmodule, _meta, [name | rest]}, _namespace, aliases, acc) do
    {acc, _aliases} = walk(rest, [name], aliases, acc)
    {acc, aliases}
  end

  defp walk({:alias, _meta, args} = ast, _namespace, aliases, acc) when is_list(args) do
    {acc, Map.merge(aliases, Map.new(ModuleName.alias_bindings(ast)))}
  end

  defp walk({:use, _meta, [{:__aliases__, _, used_parts} | _]}, namespace, aliases, {modules, uses}) do
    {{modules, [{namespace, ModuleName.resolve(used_parts, aliases)} | uses]}, aliases}
  end

  defp walk({:quote, _meta, _args}, _namespace, aliases, acc), do: {acc, aliases}

  defp walk({_, _, args}, namespace, aliases, acc) when is_list(args) do
    {acc, _aliases} = walk(args, namespace, aliases, acc)
    {acc, aliases}
  end

  defp walk({left, right}, namespace, aliases, acc) do
    {acc, aliases} = walk(left, namespace, aliases, acc)
    walk(right, namespace, aliases, acc)
  end

  defp walk(list, namespace, aliases, acc) when is_list(list) do
    Enum.reduce(list, {acc, aliases}, &walk_next(&1, &2, namespace))
  end

  defp walk(_ast, _namespace, aliases, acc), do: {acc, aliases}

  defp walk_next(ast, {acc, aliases}, namespace), do: walk(ast, namespace, aliases, acc)

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
