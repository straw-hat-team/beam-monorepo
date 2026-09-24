defmodule Trogon.Credo.ModuleCallMatcher do
  @moduledoc false

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]
  @directives [:alias, :import, :require]

  # Walks a source file and reports a call to a module one of the `pairs`
  # entries names as discouraged, once the reference is resolved through the
  # file's aliases the way `Trogon.Credo.ModuleName` resolves any other.
  #
  # Each entry in `pairs` is a tuple whose first element is the fully
  # qualified discouraged module name. The rest of the tuple is not
  # interpreted here; it is handed back to `build_issue` as-is, together with
  # the name the reference is written under and the position of the
  # reference, so that the caller decides what an issue looks like.
  #
  # A directive naming the discouraged module, an `alias`, `import`, or
  # `require`, is not a call to it and is never reported, and neither is a
  # typespec attribute such as `@spec` or `@type`. Both kinds of AST are
  # pruned before matching, since neither can hide a call underneath.
  def run(source_file, pairs, build_issue) do
    aliases = ModuleName.collect_aliases(source_file)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, pairs, aliases, build_issue))
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _pairs, _aliases, _build_issue)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  defp traverse({directive, _meta, args}, issues, _pairs, _aliases, _build_issue)
       when directive in @directives and is_list(args) do
    {[], issues}
  end

  defp traverse(
         {:., _meta, [{:__aliases__, alias_meta, parts}, _function]} = ast,
         issues,
         pairs,
         aliases,
         build_issue
       ) do
    written_name = Name.full(parts)
    resolved_name = ModuleName.resolve(parts, aliases)

    new_issues =
      pairs
      |> Enum.filter(&discourages?(&1, resolved_name))
      |> Enum.map(&build_issue.(&1, written_name, alias_meta))

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _pairs, _aliases, _build_issue), do: {ast, issues}

  defp discourages?(pair, module_name), do: elem(pair, 0) == module_name
end
