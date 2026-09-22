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

  A multi alias keeps whatever base it is written with, so
  `alias __MODULE__.{Child}` records `Child` under the name `__MODULE__.Child`,
  which no configured module matches.

  An Erlang module is collected under the name its `:as` option gives it, so
  `alias :rand, as: Random` records `Random` under `rand`, which is how such a
  module is named in a check parameter. Elixir requires the option there, since
  it cannot infer a name for an Erlang module, so an alias written without one
  binds nothing.

  A name that the file binds to more than one module, two sibling modules
  aliasing a different `Client` for instance, is mapped to `:ambiguous` rather
  than to whichever binding came last, since the file as a whole does not say
  which one a given reference means.
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

  A reference through a name the file binds to more than one module resolves to
  `nil`, which no configured module matches, since reading it as written would
  report a module that the reference does not name.
  """
  def resolve([Elixir | rest], _aliases) when rest != [], do: Name.full(rest)

  def resolve([first | rest], aliases) when is_atom(first) do
    case Map.fetch(aliases, to_string(first)) do
      {:ok, :ambiguous} -> nil
      {:ok, resolved_head} -> Name.full([resolved_head | rest])
      :error -> full([first | rest])
    end
  end

  def resolve(parts, _aliases), do: Name.full(parts)

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}, opts]}, aliases)
       when is_list(opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, {:__aliases__, _, as_parts}} ->
        {[], put_alias(aliases, full(as_parts), full(parts))}

      _ ->
        {[], put_default(aliases, parts)}
    end
  end

  defp traverse({:alias, _meta, [module, opts]}, aliases)
       when is_atom(module) and is_list(opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, {:__aliases__, _, as_parts}} ->
        {[], put_alias(aliases, full(as_parts), full(module))}

      _ ->
        {[], aliases}
    end
  end

  defp traverse({:alias, _meta, [{{:., _, [base, :{}]}, _, alias_nodes} | _opts]}, aliases) do
    base_parts = base_parts(base)

    new_aliases = Enum.reduce(alias_nodes, aliases, &put_member(&1, &2, base_parts))

    {[], new_aliases}
  end

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}]}, aliases) do
    {[], put_default(aliases, parts)}
  end

  defp traverse({:quote, _meta, _args}, aliases), do: {[], aliases}

  defp traverse(ast, aliases), do: {ast, aliases}

  defp base_parts({:__aliases__, _meta, parts}), do: parts
  defp base_parts(base), do: [base]

  defp put_member({:__aliases__, _meta, member_parts}, aliases, base_parts) do
    put_default(aliases, base_parts ++ member_parts)
  end

  defp put_member(_member, aliases, _base_parts), do: aliases

  defp put_default(aliases, parts) do
    put_alias(aliases, Name.last(parts), full(parts))
  end

  defp put_alias(aliases, name, target) do
    Map.update(aliases, name, target, &merge_target(&1, target))
  end

  defp merge_target(target, target), do: target
  defp merge_target(_existing, _target), do: :ambiguous
end
