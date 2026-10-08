defmodule Trogon.Credo.Check.Readability.MechanicalModuleName do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [],
      suffixes: ["Worker", "Job", "Manager", "Helper", "Util", "Utils"],
      hint: nil
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

      Code inside a `quote` block is not analyzed, since a module defined
      there, or a `use` written there, belongs to wherever the macro expands
      rather than to the module that defines the macro.

      This check states what is wrong with the name. A `hint` lets a project
      add, in its own words, what to do instead.
      """,
      params: [
        for_use: """
        A list of modules. When set to a non empty list, this check only
        applies to modules that `use` one of these modules. When left as the
        default empty list, the check applies to every module in the analyzed
        files. A `use` written with an explicit `Elixir.` prefix names the same
        module.
        """,
        suffixes: """
        A list of mechanical name suffixes to reject on the last segment of
        the module name. Each configured suffix also rejects the
        corresponding file name suffix, for example `"Worker"` rejects file
        names ending in `_worker.ex`.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Credo.Issue
  alias Trogon.Credo.UsingModules

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    for_use = Params.get(params, :for_use, __MODULE__)
    suffixes = Params.get(params, :suffixes, __MODULE__)
    hint = Params.get(params, :hint, __MODULE__)

    source_file
    |> UsingModules.collect(for_use)
    |> issues_for(issue_meta, suffixes, hint)
  end

  defp issues_for(modules, issue_meta, suffixes, hint) do
    {issues, well_named_meta} =
      Enum.reduce(modules, {[], nil}, &collect_module(&1, &2, issue_meta, suffixes, hint))

    issues ++ file_name_issues(issue_meta, suffixes, well_named_meta, hint)
  end

  defp collect_module(module, {issues, well_named_meta}, issue_meta, suffixes, hint) do
    last_segment = module.parts |> List.last() |> to_string()

    case Enum.find(suffixes, &String.ends_with?(last_segment, &1)) do
      nil -> {issues, well_named_meta || module.meta}
      suffix -> {[module_name_issue(issue_meta, module, suffix, hint) | issues], well_named_meta}
    end
  end

  defp file_name_issues(_issue_meta, _suffixes, nil, _hint), do: []

  defp file_name_issues(issue_meta, suffixes, meta, hint) do
    filename = IssueMeta.source_file(issue_meta).filename

    suffixes
    |> Enum.find(&String.ends_with?(filename, "_" <> Macro.underscore(&1) <> ".ex"))
    |> case do
      nil -> []
      suffix -> [file_name_issue(issue_meta, meta, suffix, hint)]
    end
  end

  defp module_name_issue(issue_meta, module, suffix, hint) do
    format_issue(
      issue_meta,
      message:
        with_hint(
          "Module name ends with the mechanical suffix `#{suffix}`. Name the module after the domain action it performs, not after the mechanism that runs it.",
          hint
        ),
      trigger: Name.full(module.parts),
      line_no: module.meta[:line],
      column: module.meta[:column]
    )
  end

  defp file_name_issue(issue_meta, meta, suffix, hint) do
    format_issue(
      issue_meta,
      message:
        with_hint(
          "File name ends with the mechanical suffix `#{suffix}`. Name the file after the domain action it performs, not after the mechanism that runs it.",
          hint
        ),
      trigger: Issue.no_trigger(),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp with_hint(message, nil), do: message
  defp with_hint(message, hint), do: "#{message} #{hint}"
end
