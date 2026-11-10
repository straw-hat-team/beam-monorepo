defmodule Trogon.Credo.Check.Readability.OneModulePerFile do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      hint: nil
    ],
    explanations: [
      check: """
      A module is found by its name, and the name is found by its path. When a file holds
      a second module, nested or beside the first, that module has no path of its own,
      and the file reads as two things at once. This matters most for a struct or an
      exception, the modules other code is written against, but it holds for any module.

          {Trogon.Credo.Check.Readability.OneModulePerFile, []}

      With the configuration above, `lib/my_app/invoice.ex` defines `MyApp.Invoice` and
      nothing else, and a `MyApp.Invoice.Line` lives in `lib/my_app/invoice/line.ex`.
      Pair it with `Trogon.Credo.Check.Readability.ModuleNameMatchesPath` to also hold
      the path to the name.

      The first `defmodule` of a file is left alone, and every `defmodule` after it, a
      nested one included, is reported where it is written.

      Code inside a `quote` block is not analyzed, since a module written there belongs
      to wherever the macro expands, which leaves macros that generate modules, structs
      or exceptions alone. A file that deliberately holds several modules silences the
      check with `# credo:disable-for-this-file`.
      """,
      params: [
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    hint = Params.get(params, :hint, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&traverse/2, [])
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.map(&issue_for(issue_meta, &1, hint))
  end

  defp traverse({:quote, _meta, _args}, acc), do: {[], acc}

  defp traverse({:defmodule, meta, [name | _]} = ast, acc), do: {ast, [{meta, module_name(name)} | acc]}

  defp traverse(ast, acc), do: {ast, acc}

  defp module_name({:__aliases__, _meta, parts}), do: if(Enum.all?(parts, &is_atom/1), do: Name.full(parts))
  defp module_name(_ast), do: nil

  defp issue_for(issue_meta, {meta, name}, hint) do
    format_issue(
      issue_meta,
      message: message(name) |> append_hint(hint),
      trigger: name || "defmodule",
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp message(nil), do: "A module is expected to be the only one in its file."
  defp message(name), do: "The module `#{name}` is expected to be the only one in its file."

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
