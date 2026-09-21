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
      Elixir does not require a module to live at the path its name implies, but
      every Elixir project is read as though it does. Once a file and its module
      disagree, the name stops being a way to find the code: a reader searching
      for `MyApp.Billing.Invoice` opens `lib/my_app/billing/invoice.ex` and finds
      something else, or nothing. The drift also accumulates silently, because
      renaming a module is a refactor everyone does and moving the file is the
      step people forget.

      Credo already ships `Credo.Check.Readability.ModuleNames`, which checks
      that a module name is CamelCase. It says nothing about where the file
      sits. This check is the complement: it does not care how a module is
      spelled, only whether its file agrees with it.

      The comparison derives the path a module name implies, rather than the
      name a path implies. It takes the outermost `defmodule` name, runs it
      through `Macro.underscore/1`, and compares the result with the file's
      path below the last path segment equal to `root`, with the extension
      dropped. That direction is deliberate: `Macro.underscore/1` is the same
      function Elixir and Mix use to turn a module name into a file name, so it
      already gets the cases a hand rolled camelize would need an acronym list
      for. `MyApp.ErrorJSON` underscores to `my_app/error_json`, and
      `MyApp.APIClient` underscores to `my_app/api_client`, both of which are
      the file names a developer actually writes. Because of this, the check
      needs no `acronyms` param.

          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "lib"]},
          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "test"]}

      With the configuration above, `lib/my_app/billing/invoice.ex` is expected
      to define `MyApp.Billing.Invoice`, and `test/my_app/billing/invoice_test.exs`
      is expected to define `MyApp.Billing.InvoiceTest`. Configuring the check
      twice, once per `root`, is how a project covers both `lib` and `test`.

      Only the outermost `defmodule` is checked. A nested module is expected to
      live in the same file as its parent, and checking it would report every
      legitimate nested module. A `defmodule` written inside a `quote` block is
      not treated as the file's outermost module either, since it belongs to
      wherever the macro expands rather than to the file that defines it. A
      file with no `defmodule` at all is skipped, and so is a file whose path
      has no segment equal to `root`, which is what keeps the check quiet on a
      config file or a mix task when a project enables it broadly.

      The check compares names, so it cannot know that two modules are the same
      thing under different spellings. A file deliberately holding a
      differently named module, a compatibility shim for instance, silences it
      with `# credo:disable-for-this-file`. That is the intended escape hatch,
      rather than a param, since the whole point of the check is that it does
      not need one to stay quiet everywhere else.

      A module written with an explicit `Elixir.` prefix, such as
      `defmodule Elixir.MyApp.Foo`, is compared as `MyApp.Foo`, since that is
      the same module. The issue is still reported at the name as written, so
      the trigger reads `Elixir.MyApp.Foo`.
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
    Enum.reduce(Enum.with_index(parts), nil, fn
      {^root, index}, _acc -> index
      _pair, acc -> acc
    end)
  end

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
