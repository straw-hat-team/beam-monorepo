defmodule Trogon.Credo.Check.Readability.RequiredUse do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      modules: [],
      message: nil,
      hint: nil
    ],
    explanations: [
      check: """
      A module that lives in a given directory is often expected to bring in a shared
      piece of behaviour: a directory of request handlers expected to `use` the
      project's handler behaviour, a directory of schemas expected to `use` the
      project's schema wrapper, a directory of tests expected to `use` the case template
      that sets up the sandbox. A file that forgets is not a compile error, it is a
      module that quietly does not get the shared setup, and that is easy to miss in
      review.

      This check is the exact inverse of `Trogon.Credo.Check.Readability.ModuleLocation`.
      That check reads "a module that uses this must live there"; this one reads "a
      module that lives here must use one of these". The two are usually enabled as a
      pair, one saying where a module must live and the other saying what a module in
      that place must bring in.

          {Trogon.Credo.Check.Readability.RequiredUse,
           [modules: [MyApp.Worker, MyApp.EventHandler],
            files: %{included: ["lib/my_app/*/processor/"]}]}

      With the configuration above, every module under a `processor/` directory is
      expected to `use` either `MyApp.Worker` or `MyApp.EventHandler`. A project scopes
      an instance of this check to a directory with Credo's own `files` param, the way
      the example does, and enables the check again with a different `files` and a
      different `modules` list for another directory.

      The check reports once per file rather than once per module, since a file is
      expected to hold a single module; a project that wants exactly one module per file
      has a separate rule to write for that. A file that defines no module at all, one
      holding only a `defimpl` block, for instance, has nothing that could carry a `use`
      and is not reported. A `use` satisfies the check no matter how deeply it is nested
      inside the file, so a file whose outer module is bare but whose nested submodule
      carries the `use` is still compliant. A `defmodule` whose name is not written as an
      alias, `defmodule Module.concat(Foo, Bar)` for instance, still counts as a module
      that must carry the `use`, but the issue it raises carries no trigger, since the
      check cannot read the module's name.

      A `use` written inside a `quote` block does not satisfy the check, since that `use`
      is injected into whichever module expands the macro rather than into the module
      the file itself defines. Aliases are resolved before matching, including the
      `Elixir.`-prefixed form, but a name the file binds to more than one module
      satisfies nothing, since the file as a whole does not say which one a reference
      means. A `use` whose module cannot be read statically, `use @behaviour` or `use
      unquote(mod)` for instance, also satisfies nothing, because the check cannot know
      what it names; a file like that needs a `# credo:disable-for-this-file` comment.

      The issue is attributed to the file's outermost module, since that is what a
      reader sees first, and its message speaks of "this directory" rather than naming
      the directory itself, since the check knows only that the file's location matched
      its `files` param, not what the project calls that place.
      """,
      params: [
        modules: """
        A list of modules. A file satisfies the check by `use`-ing any one of them,
        which is how a project says a worker or an event handler, either is fine here.
        The default empty list makes the check inert, since there is no universal
        expected module.
        """,
        message: """
        Replaces the default issue message entirely. Skipped when set to `nil`, the
        default.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to `nil`,
        the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    modules = normalize_modules(Params.get(params, :modules, __MODULE__))

    if modules == [] do
      []
    else
      context = %{modules: modules, aliases: ModuleName.collect_aliases(source_file)}

      case Credo.Code.prewalk(source_file, &traverse(&1, &2, context), {nil, false}) do
        {nil, _satisfied} ->
          []

        {_outer_module, true} ->
          []

        {{name, meta}, false} ->
          issue_meta = IssueMeta.for(source_file, params)
          message = Params.get(params, :message, __MODULE__)
          hint = Params.get(params, :hint, __MODULE__)

          [issue_for(issue_meta, meta, name, modules, message, hint)]
      end
    end
  end

  defp normalize_modules(nil), do: []
  defp normalize_modules([]), do: []

  defp normalize_modules(modules) when is_list(modules) do
    Enum.map(modules, &validate_module/1)
  end

  defp normalize_modules(modules) do
    raise ArgumentError, "invalid modules #{inspect(modules)}: expected a list of modules"
  end

  defp validate_module(module) when is_atom(module), do: ModuleName.full(module)

  defp validate_module(entry) do
    raise ArgumentError, "invalid modules entry #{inspect(entry)}: expected a module"
  end

  defp traverse({:defmodule, _meta, [{:__aliases__, alias_meta, parts} | _]} = ast, {outer, satisfied}, _context) do
    {ast, {outer || {Name.full(parts), alias_meta}, satisfied}}
  end

  defp traverse({:defmodule, meta, [_name | _]} = ast, {outer, satisfied}, _context) do
    {ast, {outer || {Credo.Issue.no_trigger(), meta}, satisfied}}
  end

  defp traverse({:use, _meta, [{:__aliases__, _, used_parts} | _]} = ast, {outer, satisfied}, context) do
    resolved = ModuleName.resolve(used_parts, context.aliases)
    {ast, {outer, satisfied or resolved in context.modules}}
  end

  defp traverse({:quote, _meta, _args}, acc, _context), do: {[], acc}

  defp traverse(ast, acc, _context), do: {ast, acc}

  defp issue_for(issue_meta, meta, name, modules, message, hint) do
    format_issue(
      issue_meta,
      message: (message || default_message(modules)) |> append_hint(hint),
      trigger: name,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp default_message([module]) do
    "A module in this directory must `use #{module}`."
  end

  defp default_message(modules) do
    list = Enum.map_join(modules, ", ", &"`#{&1}`")
    "A module in this directory must use one of these modules: #{list}."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
