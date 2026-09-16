defmodule Trogon.Credo.ModuleName do
  @moduledoc false

  alias Credo.Code.Name

  @doc """
  The fully qualified name of a module reference, with the leading `Elixir`
  segment of an explicitly rooted name such as `Elixir.Foo` removed so that it
  compares equal to the same module given as an atom in a check parameter.
  """
  def full([Elixir | rest]) when rest != [], do: Name.full(rest)
  def full(module_or_parts), do: Name.full(module_or_parts)

  @doc """
  The aliases declared anywhere in a source file, as a map of the name a module
  is written under to the fully qualified name it resolves to.

  An `alias` written inside a `quote` block is not collected, since it takes
  effect wherever the macro expands rather than in the file that defines it.
  """
  def collect_aliases(source_file) do
    Credo.Code.prewalk(source_file, &traverse/2, %{})
  end

  @doc """
  The fully qualified name that module reference parts resolve to under the
  given aliases. Only the first segment participates, mirroring how Elixir
  itself expands an alias, and a name rooted at `Elixir` bypasses aliases
  altogether.

  A reference whose first segment is not a plain name, `__MODULE__.Child` for
  instance, is rendered as written, since what it stands for is only known at
  compile time.
  """
  def resolve([Elixir | rest], _aliases) when rest != [], do: Name.full(rest)

  def resolve([first | rest], aliases) when is_atom(first) do
    case Map.fetch(aliases, to_string(first)) do
      {:ok, resolved_head} -> Name.full([resolved_head | rest])
      :error -> full([first | rest])
    end
  end

  def resolve(parts, _aliases), do: Name.full(parts)

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}, opts]}, aliases)
       when is_list(opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, {:__aliases__, _, as_parts}} ->
        {[], Map.put(aliases, full(as_parts), full(parts))}

      _ ->
        {[], put_default(aliases, parts)}
    end
  end

  defp traverse(
         {:alias, _meta, [{{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, alias_nodes}]},
         aliases
       ) do
    new_aliases =
      Enum.reduce(alias_nodes, aliases, fn
        {:__aliases__, _, member_parts}, acc -> put_default(acc, base_parts ++ member_parts)
        _member, acc -> acc
      end)

    {[], new_aliases}
  end

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}]}, aliases) do
    {[], put_default(aliases, parts)}
  end

  defp traverse({:quote, _meta, _args}, aliases), do: {[], aliases}

  defp traverse(ast, aliases), do: {ast, aliases}

  defp put_default(aliases, parts) do
    Map.put(aliases, Name.last(parts), full(parts))
  end
end
