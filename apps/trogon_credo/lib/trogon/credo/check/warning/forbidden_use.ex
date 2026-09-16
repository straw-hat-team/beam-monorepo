defmodule Trogon.Credo.Check.Warning.ForbiddenUse do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [modules: []],
    explanations: [
      check: """
      Some modules should not be brought into another module with `use`, because
      the macro they inject settles behavior at compile time and injects
      functions into the using module's public API. Building the same thing
      explicitly keeps it configurable per call site and keeps the module's
      public API its own.

      Credo already ships `Credo.Check.Warning.ForbiddenModule` to forbid a
      module outright. This check is the narrower counterpart: only `use` is
      reported, so calling the module by its full name stays allowed.

          {Trogon.Credo.Check.Warning.ForbiddenUse,
           [modules: [{MyApp.Client, "Build a client with MyApp.Client.new/1 instead."}]]}

      Aliases are resolved before matching, so a `use` written through an alias
      is reported under the name of the module it resolves to. Aliases are
      collected for the whole file rather than per lexical scope, except for an
      `alias` written inside a `quote` block, which takes effect wherever the
      macro expands and is therefore not collected.

      A name the file binds to more than one module, two sibling modules
      aliasing a different `Client` for instance, resolves to neither, since
      the file as a whole does not say which one a given reference means.

      A `use` written inside a `quote` block is reported, since the macro
      injects that `use` into every module that expands it.

      A module written with an explicit `Elixir.` prefix, such as
      `Elixir.Foo.Bar`, names the same module as `Foo.Bar` and is reported the
      same way.
      """,
      params: [
        modules: "List of modules or `{Module, \"Custom message\"}` tuples that must not be brought in with `use`."
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
         {:use, _meta, [{:__aliases__, meta, parts} | _]} = ast,
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

  defp traverse(ast, issues, _issue_meta, _modules, _aliases), do: {ast, issues}

  defp issue_for(issue_meta, meta, trigger, module, message) do
    format_issue(
      issue_meta,
      message: message || "The `#{module}` module must not be brought in with `use`.",
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
