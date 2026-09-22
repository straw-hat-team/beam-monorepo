defmodule Trogon.Credo.Check.Warning.PreferredModule do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      modules: [
        {Task, OpentelemetryProcessPropagator.Task},
        {Task.Supervisor, OpentelemetryProcessPropagator.Task.Supervisor}
      ]
    ],
    explanations: [
      check: """
      Some modules have a drop-in replacement that should be preferred over
      the original because it wraps additional behaviour around it, for
      example preserving OpenTelemetry context across a spawned process.

      Use this check to flag calls to the discouraged module when a preferred
      module is configured to replace it.

      The default `modules` value targets `OpentelemetryProcessPropagator`, so
      projects that do not use OpenTelemetry should override `modules`.

      Aliases are collected for the whole file rather than per lexical scope,
      so a module that aliases the preferred module suppresses findings
      across the entire file. An `alias` written inside a `quote` block is the
      exception: it takes effect wherever the macro expands, so it is not
      collected.

      A name the file binds to more than one module, two sibling modules
      aliasing a different `Client` for instance, matches neither module, and
      does not fall back to matching the name as written either, since the file
      as a whole does not say which one a given reference means.

      Typespecs are not reported, since naming the discouraged module in a
      `@spec` or a `@type` is not a call to it.

      A module written with an explicit `Elixir.` prefix, such as
      `Elixir.Task`, names the same module as `Task` and is reported the same
      way.

      Naming the module in an `alias`, `import`, or `require` is not a call to
      it, so directives are never reported. That includes the multi alias form
      `Task.{Supervisor}`, which shares its AST shape with a function call.

      The OpenTelemetry process propagator rule this check generalizes was
      originally described by David Bernheisel.
      """,
      params: [
        modules: "List of `{Discouraged, Preferred}` or `{Discouraged, Preferred, \"Custom message\"}` tuples."
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]
  @directives [:alias, :import, :require]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    pairs = prepare_pairs(Params.get(params, :modules, __MODULE__))
    issue_meta = IssueMeta.for(source_file, params)
    aliases = ModuleName.collect_aliases(source_file)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, pairs, aliases))
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _issue_meta, _pairs, _aliases)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  defp traverse({directive, _meta, args}, issues, _issue_meta, _pairs, _aliases)
       when directive in @directives and is_list(args) do
    {[], issues}
  end

  defp traverse(
         {:., _meta, [{:__aliases__, alias_meta, parts}, _function]} = ast,
         issues,
         issue_meta,
         pairs,
         aliases
       ) do
    written_name = Name.full(parts)
    resolved_name = ModuleName.resolve(parts, aliases)

    new_issues =
      pairs
      |> Enum.filter(fn {discouraged, _preferred, _message} -> discouraged == resolved_name end)
      |> Enum.map(fn {discouraged, preferred, message} ->
        issue_for(issue_meta, alias_meta, written_name, discouraged, preferred, message)
      end)

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta, _pairs, _aliases), do: {ast, issues}

  defp issue_for(issue_meta, meta, trigger, discouraged, preferred, message) do
    format_issue(
      issue_meta,
      message: message || "Use `#{preferred}` instead of `#{discouraged}`.",
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp prepare_pairs(modules) do
    Enum.map(modules, &prepare_pair/1)
  end

  defp prepare_pair({discouraged, preferred, message}) do
    {ModuleName.full(discouraged), ModuleName.full(preferred), message}
  end

  defp prepare_pair({discouraged, preferred}) do
    {ModuleName.full(discouraged), ModuleName.full(preferred), nil}
  end
end
