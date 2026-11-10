defmodule Trogon.Credo.Check.Readability.StructOwnFile do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      hint: nil
    ],
    explanations: [
      check: """
      A struct is a data type other code is written against, so it is the module people
      look for by name. When its `defstruct`, or the `defexception` of an exception, shares
      a file with another module, a nested one or a sibling, the struct stops being
      findable by path, and the file reads as two things at once.

          {Trogon.Credo.Check.Readability.StructOwnFile, []}

      With the configuration above, a file holding a `defstruct` or `defexception` is expected to define
      that one module and nothing else, so `lib/my_app/invoice.ex` defines
      `MyApp.Invoice` and a `MyApp.Invoice.Line` struct lives in
      `lib/my_app/invoice/line.ex`. Pair it with
      `Trogon.Credo.Check.Readability.ModuleNameMatchesPath` to also hold the path to the
      name.

      The check counts every `defmodule` the file writes, nested ones included, and
      reports each `defstruct` and `defexception` when there is more than one. A file with
      a single module is never reported.

      Code inside a `quote` block is not analyzed, since a `defstruct`, `defexception` or
      `defmodule` written there belongs to wherever the macro expands. That is what leaves macros
      that generate structs alone. A file that deliberately shares a struct with another
      module silences the check with `# credo:disable-for-this-file`.
      """,
      params: [
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    hint = Params.get(params, :hint, __MODULE__)

    {modules, structs} = Credo.Code.prewalk(source_file, &traverse/2, {0, []})

    if modules > 1 do
      structs |> Enum.reverse() |> Enum.map(&issue_for(issue_meta, &1, hint))
    else
      []
    end
  end

  defp traverse({:quote, _meta, _args}, acc), do: {[], acc}

  defp traverse({:defmodule, _meta, _args} = ast, {modules, structs}), do: {ast, {modules + 1, structs}}

  defp traverse({definer, meta, [_ | _]} = ast, {modules, structs}) when definer in [:defstruct, :defexception],
    do: {ast, {modules, [{definer, meta} | structs]}}

  defp traverse(ast, acc), do: {ast, acc}

  defp issue_for(issue_meta, {definer, meta}, hint) do
    format_issue(
      issue_meta,
      message: "A `#{definer}` is expected to be the only module in its file." |> append_hint(hint),
      trigger: to_string(definer),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
