defmodule Trogon.Credo.Check.Oban.WorkerName do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [Oban.Worker, Oban.Pro.Worker],
      suffixes: ["Worker", "Processor"],
      hint: nil
    ],
    explanations: [
      check: """
      A worker is named the way any other module is: as the agent noun for the
      verb it performs, with the domain action at the end of the name.
      `InvoiceReminder` and `WelcomeEmailSender` name a module that way, and so
      does an action name such as `SendWelcomeEmail`. Either way, the last word
      of the name says what the module does.

      Appending `Worker` pushes a second agent noun onto the end, and that one
      names the mechanism instead of the action. `InvoiceReminderWorker` reads
      as "the thing that works on invoice reminding", which, turned back into a
      verb phrase, is `WorkRemindInvoice`: the domain verb stops being the head
      of the name. `Processor` has the same problem. `InvoiceReminderProcessor`
      reads as `ProcessInvoiceReminder`, so the verb in the name becomes
      "process" instead of "remind".

      Whether a module is an Oban job is already visible from its
      `use Oban.Worker` or `use Oban.Pro.Worker` line, and from the directory it
      lives in for a project that organizes jobs that way, so restating the
      mechanism in the name is redundant and forces a rename whenever the
      mechanism changes.

      This check reports a module that `use`s a worker module and whose name
      ends with one of the suffixes.

          # preferred
          defmodule MyApp.Billing.InvoiceReminder do
            use Oban.Worker, queue: :mailers
          end

          # NOT preferred
          defmodule MyApp.Billing.InvoiceReminderWorker do
            use Oban.Worker, queue: :mailers
          end

      The same reasoning applies to the file name: a file named
      `invoice_reminder_worker.ex` restates the mechanism as well. The file
      name is reported at most once, no matter how many modules the file holds.

      Renaming a worker that is already deployed changes the name the next job
      is stored under, while jobs already in `oban_jobs` keep the old one and
      no longer find a module to run. The message says so, and points at the
      `aliases:` option of `use Oban.Pro.Worker` for keeping the old name
      working while those jobs drain.

      A nested `defmodule` is named with the namespace of the one enclosing it,
      a `use` written through an alias is matched under the module it resolves
      to where it is written, so an alias in a sibling module does not change
      it, and code inside a `quote` block is not analyzed, since a module
      defined there belongs to wherever the macro expands.
      """,
      params: [
        for_use: """
        A list of worker modules. A module that `use`s one of them must not end
        its name with a suffix in `suffixes`. Defaults to `[Oban.Worker,
        Oban.Pro.Worker]`. An empty list makes the check inert.
        """,
        suffixes: """
        A list of mechanism suffixes to reject on the last segment of a worker
        module's name. Each configured suffix also rejects the corresponding
        file name suffix, for example `"Worker"` rejects file names ending in
        `_worker.ex`. Defaults to `["Worker", "Processor"]`.
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
  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    case params |> Params.get(:for_use, __MODULE__) |> List.wrap() do
      [] -> []
      for_use -> issues(source_file, params, for_use)
    end
  end

  defp issues(source_file, params, for_use) do
    issue_meta = IssueMeta.for(source_file, params)
    suffixes = Params.get(params, :suffixes, __MODULE__)
    hint = Params.get(params, :hint, __MODULE__)

    {issues, well_named_meta} =
      source_file
      |> ModuleDeclaration.collect_module_declarations(using: for_use)
      |> Enum.reduce({[], nil}, &collect_module(&1, &2, issue_meta, suffixes, hint))

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
    name = ModuleName.full(module.namespace)

    message =
      "Worker module `#{name}` ends with `#{suffix}`, which names the mechanism that runs it " <>
        "instead of the action it performs. Drop the suffix and name the module after what it " <>
        "does. If the worker is already deployed, jobs in `oban_jobs` store its current name, " <>
        "so keep that name working with `aliases:` on `use Oban.Pro.Worker` when renaming it."

    format_issue(
      issue_meta,
      message: append_hint(message, hint),
      trigger: Name.full(module.parts),
      line_no: module.meta[:line],
      column: module.meta[:column]
    )
  end

  defp file_name_issue(issue_meta, meta, suffix, hint) do
    message =
      "File name ends with the mechanism suffix `#{suffix}`. Name the file after the action the " <>
        "worker performs, not after the mechanism that runs it."

    format_issue(
      issue_meta,
      message: append_hint(message, hint),
      trigger: Issue.no_trigger(),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
