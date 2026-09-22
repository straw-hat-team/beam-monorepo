defmodule Trogon.Credo.Check.Readability.ModuleNameMatchesPath do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      root: nil,
      hint: nil
    ],
    explanations: [
      check: """
      Elixir does not require a module to live at the path its name implies, but every
      Elixir project is read as though it does. Once a file and its module disagree,
      the name stops being a way to find the code: a reader searching for
      `MyApp.Billing.Invoice` opens `lib/my_app/billing/invoice.ex` and finds something
      else, or nothing. The drift also accumulates silently, because renaming a module
      is a refactor everyone does and moving the file is the step people forget.

          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "lib"]},
          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "test"]}

      With the configuration above, `lib/my_app/billing/invoice.ex` is expected to
      define `MyApp.Billing.Invoice`, and `test/my_app/billing/invoice_test.exs` to
      define `MyApp.Billing.InvoiceTest`. Configuring the check once per `root` is how
      a project covers both trees.

      The comparison runs the outermost `defmodule` name through `Macro.underscore/1`
      and compares the result with the file's path below the last path segment equal to
      `root`, with the extension dropped. Deriving the path a name implies, rather than
      the name a path implies, is deliberate: `Macro.underscore/1` is the same function
      Elixir and Mix use for this, so it already gets the cases a hand rolled camelize
      would need an acronym list for. `MyApp.ErrorJSON` underscores to
      `my_app/error_json` and `MyApp.APIClient` to `my_app/api_client`, both of which
      are the file names a developer actually writes, so the check needs no `acronyms`
      param.

      Credo already ships `Credo.Check.Readability.ModuleNames`, which checks that a
      module name is CamelCase and says nothing about where the file sits. This check
      is the complement: it does not care how a module is spelled, only whether its
      file agrees with it.

      Only the outermost `defmodule` is checked, since a nested module is expected to
      share its parent's file and checking it would report every legitimate one. A
      `defmodule` written inside a `quote` block is not treated as the file's outermost
      module either, since it belongs to wherever the macro expands. A file with no
      `defmodule` at all, or whose path has no segment equal to `root`, is skipped,
      which is what keeps the check quiet on a config file or a mix task when a project
      enables it broadly.

      The check compares names, so it cannot know that two modules are the same thing
      under different spellings. A file deliberately holding a differently named
      module, a compatibility shim for instance, silences it with
      `# credo:disable-for-this-file`. A module written as `defmodule Elixir.MyApp.Foo`
      is compared as `MyApp.Foo`, since that is the same module, though the issue is
      still reported at the name as written.
      """,
      params: [
        root: """
        The path segment below which the mirroring is expected to hold. A file
        whose path has no segment equal to `root` is skipped. When a path has
        more than one segment equal to `root`, the last one is used. Skipped
        when set to `nil`, the default, or to an empty list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    root = normalize_root(Params.get(params, :root, __MODULE__))

    if root == nil do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        root: root,
        hint: Params.get(params, :hint, __MODULE__)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    end
  end

  defp normalize_root(nil), do: nil
  defp normalize_root([]), do: nil
  defp normalize_root(root) when is_binary(root) or is_atom(root), do: to_string(root)

  defp normalize_root(root) do
    raise ArgumentError, "invalid root #{inspect(root)}: expected a string or an atom"
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse({:defmodule, _meta, [{:__aliases__, alias_meta, parts} | _]}, issues, context) do
    {[], check_module(parts, alias_meta, issues, context)}
  end

  defp traverse({:defmodule, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp check_module(parts, meta, issues, context) do
    %{issue_meta: issue_meta, root: root} = context
    source_file = IssueMeta.source_file(issue_meta)
    path_parts = Path.split(source_file.filename)

    case last_index(path_parts, root) do
      nil -> issues
      index -> check_after_root(Enum.drop(path_parts, index + 1), parts, meta, issues, context)
    end
  end

  defp check_after_root([], _parts, _meta, issues, _context), do: issues

  defp check_after_root(after_root, parts, meta, issues, context) do
    %{issue_meta: issue_meta, root: root, hint: hint} = context
    module_name = ModuleName.full(parts)
    expected_relative = Macro.underscore(module_name)
    {actual_relative, extension} = split_relative(after_root)

    if actual_relative == expected_relative do
      issues
    else
      trigger = Name.full(parts)
      [issue_for(issue_meta, meta, trigger, module_name, root, expected_relative, extension, hint) | issues]
    end
  end

  defp last_index(parts, root) do
    parts
    |> Enum.with_index()
    |> Enum.reduce(nil, &last_root_index(&1, &2, root))
  end

  defp last_root_index({root, index}, _acc, root), do: index
  defp last_root_index(_pair, acc, _root), do: acc

  defp split_relative(parts) do
    {directories, [filename]} = Enum.split(parts, -1)
    extension = Path.extname(filename)
    relative = Enum.join(directories ++ [Path.rootname(filename)], "/")

    {relative, extension}
  end

  defp issue_for(issue_meta, meta, trigger, module_name, root, expected_relative, extension, hint) do
    format_issue(
      issue_meta,
      message: message(module_name, root, expected_relative, extension) |> append_hint(hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp message(module_name, root, expected_relative, extension) do
    "The module `#{module_name}` is expected in `#{root}/#{expected_relative}#{extension}`."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
