defmodule Trogon.Credo.Check.Readability.MechanicalModuleName do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [],
      suffixes: ["Worker", "Job", "Manager", "Helper", "Util", "Utils"]
    ],
    explanations: [
      check: """
      A module should be named after the domain role it performs, not after the
      execution mechanism that happens to run it.

      Whether a module runs as a background job, a GenServer, or anything else
      is already visible from its `use` line, so restating the mechanism in the
      name is redundant and forces a rename whenever the mechanism changes.

          # preferred
          defmodule MyApp.Jobs.SendWelcomeEmail do
            use Oban.Worker
          end

          # NOT preferred
          defmodule MyApp.Jobs.SendWelcomeEmailWorker do
            use Oban.Worker
          end

      The same reasoning applies to the file name: a file named
      `send_welcome_email_worker.ex` restates the mechanism as well. The file
      name is reported at most once, no matter how many modules the file holds.

      The default `suffixes` list is opinionated. Projects should trim it down
      to the conventions they actually want enforced.
      """,
      params: [
        for_use: """
        A list of modules. When set to a non empty list, this check only
        applies to modules that `use` one of these modules. When left as the
        default empty list, the check applies to every module in the analyzed
        files.
        """,
        suffixes: """
        A list of mechanical name suffixes to reject on the last segment of
        the module name. Each configured suffix also rejects the
        corresponding file name suffix, for example `"Worker"` rejects file
        names ending in `_worker.ex`.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Credo.Issue

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    for_use = params |> Params.get(:for_use, __MODULE__) |> Enum.map(&Name.full/1)
    suffixes = Params.get(params, :suffixes, __MODULE__)

    {modules, uses} = Credo.Code.prewalk(source_file, &traverse/2, {[], []})

    modules
    |> Enum.reverse()
    |> Enum.filter(&applies_to?(&1, uses, for_use))
    |> issues_for(issue_meta, suffixes)
  end

  defp traverse({:defmodule, _meta, [{:__aliases__, meta, parts} | rest]}, acc) do
    {[], walk(rest, parts, put_module(acc, parts, parts, meta))}
  end

  defp traverse(ast, acc), do: {ast, acc}

  # Manual recursion (mirroring `traverse/2` above) so that a nested
  # `defmodule` extends the namespace of the enclosing one and a `use` site is
  # attributed to its enclosing module's fully qualified name.
  defp walk({:defmodule, _meta, [{:__aliases__, meta, parts} | rest]}, namespace, acc) do
    full_namespace = namespace ++ parts

    walk(rest, full_namespace, put_module(acc, full_namespace, parts, meta))
  end

  defp walk({:use, _meta, [{:__aliases__, _, used_parts} | _]}, namespace, {modules, uses}) do
    {modules, [{namespace, Name.full(used_parts)} | uses]}
  end

  defp walk({_, _, args}, namespace, acc) when is_list(args) do
    walk(args, namespace, acc)
  end

  defp walk({left, right}, namespace, acc) do
    walk(right, namespace, walk(left, namespace, acc))
  end

  defp walk(list, namespace, acc) when is_list(list) do
    Enum.reduce(list, acc, &walk(&1, namespace, &2))
  end

  defp walk(_ast, _namespace, acc), do: acc

  defp put_module({modules, uses}, namespace, parts, meta) do
    {[%{namespace: namespace, parts: parts, meta: meta} | modules], uses}
  end

  defp applies_to?(_module, _uses, []), do: true

  defp applies_to?(module, uses, for_use) do
    Enum.any?(uses, fn {namespace, used} ->
      namespace == module.namespace and used in for_use
    end)
  end

  defp issues_for(modules, issue_meta, suffixes) do
    {issues, well_named_meta} =
      Enum.reduce(modules, {[], nil}, fn module, {issues, well_named_meta} ->
        last_segment = module.parts |> List.last() |> to_string()

        case Enum.find(suffixes, &String.ends_with?(last_segment, &1)) do
          nil -> {issues, well_named_meta || module.meta}
          suffix -> {[module_name_issue(issue_meta, module, suffix) | issues], well_named_meta}
        end
      end)

    issues ++ file_name_issues(issue_meta, suffixes, well_named_meta)
  end

  defp file_name_issues(_issue_meta, _suffixes, nil), do: []

  defp file_name_issues(issue_meta, suffixes, meta) do
    filename = IssueMeta.source_file(issue_meta).filename

    suffixes
    |> Enum.find(&String.ends_with?(filename, "_" <> Macro.underscore(&1) <> ".ex"))
    |> case do
      nil -> []
      suffix -> [file_name_issue(issue_meta, meta, suffix)]
    end
  end

  defp module_name_issue(issue_meta, module, suffix) do
    format_issue(
      issue_meta,
      message:
        "Module name ends with the mechanical suffix `#{suffix}`. Name the module after the domain action it performs, not after the mechanism that runs it.",
      trigger: Name.full(module.parts),
      line_no: module.meta[:line],
      column: module.meta[:column]
    )
  end

  defp file_name_issue(issue_meta, meta, suffix) do
    format_issue(
      issue_meta,
      message:
        "File name ends with the mechanical suffix `#{suffix}`. Name the file after the domain action it performs, not after the mechanism that runs it.",
      trigger: Issue.no_trigger(),
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
