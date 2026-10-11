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
      Elixir project is read as though it does. Once a file and its module disagree, the
      name stops being a way to find the code, and the drift accumulates silently:
      renaming a module is a refactor everyone does and moving the file is the step
      people forget.

          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "lib"]},
          {Trogon.Credo.Check.Readability.ModuleNameMatchesPath, [root: "test"]}

      With the configuration above, `lib/my_app/billing/invoice.ex` is expected to
      define `MyApp.Billing.Invoice`, and `test/my_app/billing/invoice_test.exs` to
      define `MyApp.Billing.InvoiceTest`. Configuring the check once per `root` is how a
      project covers both trees.

      The outermost `defmodule` name goes through `Macro.underscore/1` and is compared
      with the file's path below a segment equal to `root`, extension dropped. Deriving
      the path from the name is what lets the check skip an `acronyms` param, since
      `Macro.underscore/1` is the function Elixir and Mix already use for this:
      `MyApp.ErrorJSON` gives `my_app/error_json` and `MyApp.APIClient` gives
      `my_app/api_client`, which are the file names a developer actually writes. A path
      whose own namespace repeats the root, `lib/my_app/lib/foo.ex` for instance, is
      read from whichever `lib` makes the name agree.

      Only the file's first `defmodule` is checked, since a nested module shares its
      parent's file, and a file holding several top-level modules can only have one of
      them agree with the path. A `defmodule` inside a `quote` block is not the file's
      first module either, since it belongs to wherever the macro expands. A file with
      no `defmodule`, or whose path has no segment equal to `root`, is skipped, which is
      what keeps the check quiet on a config file or a mix task.

      The check compares names, so a file deliberately holding a differently named
      module, a compatibility shim for instance, silences it with
      `# credo:disable-for-this-file`. `defmodule Elixir.MyApp.Foo` is compared as
      `MyApp.Foo`, since that is the same module, though the issue is reported at the
      name as written.

      Credo's `Credo.Check.Readability.ModuleNames` checks that a name is CamelCase and
      says nothing about where its file sits. This check is the complement.
      """,
      params: [
        root: """
        The path segment below which the mirroring is expected to hold. A file
        whose path has no segment equal to `root` is skipped. When a path has
        more than one segment equal to `root`, a module matching the path below
        any one of them is accepted, and an issue names the outermost. Skipped
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

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context), {false, []})
      |> elem(1)
    end
  end

  defp normalize_root(nil), do: nil
  defp normalize_root([]), do: nil
  defp normalize_root(root) when is_binary(root) or is_atom(root), do: to_string(root)

  defp normalize_root(root) do
    raise ArgumentError, "invalid root #{inspect(root)}: expected a string or an atom"
  end

  defp traverse({:quote, _meta, _args}, acc, _context), do: {[], acc}

  defp traverse({:defmodule, _meta, _args}, {true, issues}, _context), do: {[], {true, issues}}

  defp traverse({:defmodule, _meta, [{:__aliases__, alias_meta, parts} | _]}, {false, issues}, context) do
    {[], {true, check_module(parts, alias_meta, issues, context)}}
  end

  defp traverse({:defmodule, _meta, _args}, {false, issues}, _context), do: {[], {true, issues}}

  defp traverse(ast, acc, _context), do: {ast, acc}

  defp check_module(parts, meta, issues, context) do
    source_file = IssueMeta.source_file(context.issue_meta)

    source_file.filename
    |> Path.split()
    |> root_candidates(context.root)
    |> check_candidates(parts, meta, issues, context)
  end

  defp check_candidates([], _parts, _meta, issues, _context), do: issues

  defp check_candidates([outermost | _] = candidates, parts, meta, issues, context) do
    %{issue_meta: issue_meta, root: root, hint: hint} = context
    module_name = ModuleName.full(parts)
    expected_relative = Macro.underscore(module_name)

    if Enum.any?(candidates, &(relative(&1) == expected_relative)) do
      issues
    else
      trigger = Name.full(parts)
      extension = extension(outermost)
      [issue_for(issue_meta, meta, trigger, module_name, root, expected_relative, extension, hint) | issues]
    end
  end

  defp root_candidates(path_parts, root) do
    path_parts
    |> Enum.with_index()
    |> Enum.flat_map(&candidate(&1, path_parts, root))
  end

  defp candidate({root, index}, path_parts, root) do
    case Enum.drop(path_parts, index + 1) do
      [] -> []
      after_root -> [after_root]
    end
  end

  defp candidate(_pair, _path_parts, _root), do: []

  defp relative(parts) do
    {directories, [filename]} = Enum.split(parts, -1)

    Enum.join(directories ++ [Path.rootname(filename)], "/")
  end

  defp extension(parts) do
    parts |> List.last() |> Path.extname()
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
