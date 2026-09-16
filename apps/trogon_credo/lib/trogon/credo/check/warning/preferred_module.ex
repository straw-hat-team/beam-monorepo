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
      across the entire file.

      Typespecs are not reported, since naming the discouraged module in a
      `@spec` or a `@type` is not a call to it.

      The OpenTelemetry process propagator rule this check generalizes was
      originally described by David Bernheisel.
      """,
      params: [
        modules: "List of `{Discouraged, Preferred}` or `{Discouraged, Preferred, \"Custom message\"}` tuples."
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.Aliases

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    pairs = prepare_pairs(Params.get(params, :modules, __MODULE__))
    issue_meta = IssueMeta.for(source_file, params)
    aliases = Aliases.collect(source_file)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, pairs, aliases))
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _issue_meta, _pairs, _aliases)
       when attribute in @typespec_attributes do
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
    resolved_name = Aliases.resolve(parts, aliases)

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
    Enum.map(modules, fn
      {discouraged, preferred, message} -> {Name.full(discouraged), Name.full(preferred), message}
      {discouraged, preferred} -> {Name.full(discouraged), Name.full(preferred), nil}
    end)
  end
end
