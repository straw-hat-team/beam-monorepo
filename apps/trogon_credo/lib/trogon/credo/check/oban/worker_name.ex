defmodule Trogon.Credo.Check.Oban.WorkerName do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [Oban.Worker, Oban.Pro.Worker],
      suffix: "Worker",
      hint: nil
    ],
    explanations: [
      check: """
      A worker module is more than code: Oban stores its name in the `worker`
      column of every job it inserts, and looks the module up by that name when the
      job runs. Ending every worker's name with `Worker` makes that obvious where
      the module is defined, where it is enqueued, and in the `oban_jobs` table,
      so nobody renames one thinking only code refers to it.

      This check reports a module that `use`s a worker module and whose name does
      not end with the suffix.

          # preferred
          defmodule MyApp.SendWelcomeEmailWorker do
            use Oban.Worker, queue: :mailers
          end

          # NOT preferred
          defmodule MyApp.SendWelcomeEmail do
            use Oban.Worker, queue: :mailers
          end

      Renaming a worker that is already deployed changes the name the next job is
      stored under, while the jobs already in `oban_jobs` keep the old one and no
      longer find a module to run. The message says so, and points at the
      `aliases:` option of `use Oban.Pro.Worker` for keeping the old name working
      while those jobs drain.

      `Trogon.Credo.Check.Readability.MechanicalModuleName` rejects the `Worker`
      suffix by default. A project that enables both drops `"Worker"` from that
      check's `suffixes`.

      A nested `defmodule` is named with the namespace of the one enclosing it, a
      `use` written through an alias is matched under the module it resolves to,
      and code inside a `quote` block is not analyzed, since a module defined
      there belongs to wherever the macro expands.
      """,
      params: [
        for_use: """
        A list of worker modules. A module that `use`s one of them must end its
        name with the suffix. Defaults to `[Oban.Worker, Oban.Pro.Worker]`. An
        empty list makes the check inert.
        """,
        suffix: """
        The suffix the last segment of a worker module's name must end with.
        Defaults to `"Worker"`.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.UsingModules

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
    suffix = Params.get(params, :suffix, __MODULE__)
    hint = Params.get(params, :hint, __MODULE__)

    source_file
    |> UsingModules.collect(for_use)
    |> Enum.reject(&(&1.parts |> List.last() |> to_string() |> String.ends_with?(suffix)))
    |> Enum.map(&issue_for(issue_meta, &1, suffix, hint))
  end

  defp issue_for(issue_meta, module, suffix, hint) do
    message =
      "Worker module name must end with `#{suffix}`. If the worker is already deployed, jobs in " <>
        "`oban_jobs` store its current name, so keep that name working with `aliases:` on " <>
        "`use Oban.Pro.Worker` when renaming it."

    format_issue(
      issue_meta,
      message: append_hint(message, hint),
      trigger: Name.full(module.parts),
      line_no: module.meta[:line],
      column: module.meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
