defmodule Trogon.Credo.Check.Warning.ForbiddenImport do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [modules: []],
    explanations: [
      check: """
      Some modules are only meant to be called with a fully qualified name, either
      because they are meant for a specific context (like test support helpers) or
      because importing them hides where a function comes from.

      Credo already ships `Credo.Check.Warning.ForbiddenModule` to forbid usage of a
      module altogether. This check is the narrower counterpart: it only forbids
      `import`-ing the module, while calling it with its full name remains allowed.

      Aliases are resolved before matching, so an `import` written through an
      alias is reported under the name of the module it resolves to. Aliases are
      collected for the whole file rather than per lexical scope, except for an
      `alias` written inside a `quote` block, which takes effect wherever the
      macro expands and is therefore not collected.

      A module written with an explicit `Elixir.` prefix, such as
      `Elixir.Foo.Bar`, names the same module as `Foo.Bar` and is reported
      the same way.
      """,
      params: [
        modules: "List of modules or `{Module, \"Custom message\"}` tuples that must not be imported."
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    modules = prepare_modules(Params.get(params, :modules, __MODULE__))
    issue_meta = IssueMeta.for(source_file, params)
    aliases = ModuleName.collect_aliases(source_file)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, modules, aliases))
  end

  defp traverse(
         {:import, _meta, [{:__aliases__, meta, parts} | _]} = ast,
         issues,
         issue_meta,
         modules,
         aliases
       ) do
    module = ModuleName.resolve(parts, aliases)

    case Map.fetch(modules, module) do
      {:ok, message} ->
        {ast, [issue_for(issue_meta, meta, Name.full(parts), module, message) | issues]}

      :error ->
        {ast, issues}
    end
  end

  defp traverse(
         {:import, _meta,
          [
            {{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, alias_nodes}
            | _
          ]} = ast,
         issues,
         issue_meta,
         modules,
         aliases
       ) do
    new_issues =
      Enum.reduce(alias_nodes, [], fn
        {:__aliases__, meta, member_parts}, acc ->
          module = ModuleName.resolve(base_parts ++ member_parts, aliases)
          trigger = Name.full(member_parts)

          case Map.fetch(modules, module) do
            {:ok, message} -> [issue_for(issue_meta, meta, trigger, module, message) | acc]
            :error -> acc
          end

        _member, acc ->
          acc
      end)

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta, _modules, _aliases), do: {ast, issues}

  defp issue_for(issue_meta, meta, trigger, module, message) do
    format_issue(
      issue_meta,
      message: message || "The `#{module}` module must not be imported.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp prepare_modules(modules) do
    modules
    |> Enum.map(fn
      {module, message} -> {ModuleName.full(module), message}
      module -> {ModuleName.full(module), nil}
    end)
    |> Map.new()
  end
end
