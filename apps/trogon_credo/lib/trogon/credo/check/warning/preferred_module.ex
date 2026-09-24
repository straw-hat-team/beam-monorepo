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

      Every call to the discouraged module is reported, whatever the function,
      so the preferred module is expected to be a complete drop-in that covers
      the whole public API of the module it replaces. A call such as
      `Task.await/1` is reported even though awaiting a task does not spawn a
      process, and the fix is to call it through the preferred module too, not
      to disable the check.

      The default `modules` value targets `OpentelemetryProcessPropagator`,
      the same pair `Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation`
      reports on its own, with a message that explains why losing OpenTelemetry
      context matters and how to point a project at its own wrapper module.
      A project that enables that check should override this check's `modules`
      to drop the OTel pair, so a `Task` call is not reported twice. Projects
      that do not use OpenTelemetry should override `modules` too.

      A project can prefer a module of its own, such as a `MyApp.Task` that
      picks its implementation at compile time and delegates to it. Overriding
      `modules` replaces the default, so list `OpentelemetryProcessPropagator.Task`
      as a discouraged module as well if calls to it should also go through
      `MyApp.Task`. A `defdelegate` whose `to:` names the discouraged module is
      not a call to it, so the preferred module itself is not reported for
      delegating.

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

  alias Trogon.Credo.ModuleCallMatcher
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    pairs = prepare_pairs(Params.get(params, :modules, __MODULE__))
    issue_meta = IssueMeta.for(source_file, params)
    ModuleCallMatcher.run(source_file, pairs, &issue_for(issue_meta, &1, &2, &3))
  end

  defp issue_for(issue_meta, {discouraged, preferred, message}, trigger, meta) do
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
