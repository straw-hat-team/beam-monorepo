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
      or exceptions alone. Neither is a `defmodule` written inside a function body, a
      `def`, `defp`, `defmacro`, `test`, `setup`, `fn` or `&` capture: that module is a
      value the code builds while it runs, such as a test defining a module to exercise
      a `use` macro, and it has no path to be found by. A `defmodule` in a module body
      is reported, whether it sits directly there, under an `if`, inside a `describe`,
      or in a module attribute. A file that deliberately holds several modules silences
      the check with `# credo:disable-for-this-file`.
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
    |> SourceFile.ast()
    |> collect([])
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.map(&issue_for(issue_meta, &1, hint))
  end

  @runtime_scopes [:quote, :fn, :def, :defp, :defmacro, :defmacrop, :test, :setup, :setup_all, :on_exit]

  defp collect({:@, _meta, [{_name, _attr_meta, value}]}, acc), do: collect(value, acc)

  defp collect({:&, _meta, [{:/, _slash_meta, [function, _arity]}]}, acc), do: collect(function, acc)
  defp collect({:&, _meta, _body}, acc), do: acc

  defp collect({scope, _meta, _args}, acc) when scope in @runtime_scopes, do: acc

  defp collect({:defmodule, meta, [name | rest]}, acc), do: collect(rest, [{meta, module_name(name)} | acc])

  defp collect({form, _meta, args}, acc), do: collect(args, collect(form, acc))
  defp collect({left, right}, acc), do: collect(right, collect(left, acc))
  defp collect(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect/2)
  defp collect(_ast, acc), do: acc

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
