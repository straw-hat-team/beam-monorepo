defmodule Trogon.Credo.Check.Ecto.MultiRunRepo do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [hint: nil],
    explanations: [
      check: """
      `Ecto.Multi.run` hands its callback the repo that runs the transaction. A
      callback that ignores it, and reaches a repo module by name instead, only stays
      inside the transaction while the two happen to be the same repo. Once they are
      not, a read replica named by a helper or a second repo running the `Ecto.Multi`
      for instance, the step runs on a connection of its own: its writes survive a
      rollback, its reads can see data the transaction has not, and a `FOR UPDATE` it
      takes is released as soon as the statement ends.

          # preferred
          Ecto.Multi.run(multi, :lock, fn repo, _changes ->
            {:ok, lock_replay(repo, replay_id)}
          end)

          # NOT preferred
          Ecto.Multi.run(multi, :lock, fn _repo, _changes ->
            {:ok, lock_replay(replay_id)}
          end)

      Whether a function a callback calls reaches a repo cannot be seen from here, so
      the check asks every callback to use its repo, and a step that touches no
      database is reported as well. Such a step says so with a disable comment, or
      belongs outside the `Ecto.Multi`.

      Reported: an anonymous function given to `Ecto.Multi.run/3`, called directly,
      through an alias, or piped, whose first parameter is `_` or a name starting with
      an underscore. Each clause of a multi-clause function is read on its own.

      Not reported: `Ecto.Multi.run/5`, a capture such as `&lock/2`, and a function
      held in a variable, since none of them shows the parameter the callback binds.
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
  alias Trogon.Credo.ModuleName

  @multi_module "Ecto.Multi"
  @message "An `Ecto.Multi.run` callback must use the repo it is given, so its queries run on " <>
             "the connection of the transaction that runs the `Ecto.Multi`."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    context = %{
      issue_meta: IssueMeta.for(source_file, params),
      hint: Params.get(params, :hint, __MODULE__),
      aliases: ModuleName.collect_aliases(source_file)
    }

    Credo.Code.prewalk(source_file, &traverse(&1, &2, context))
  end

  defp traverse({{:., _dot_meta, [{:__aliases__, _alias_meta, parts}, :run]}, _call_meta, args} = ast, issues, context)
       when length(args) in [2, 3] do
    if ModuleName.resolve(parts, context.aliases) == @multi_module do
      {ast, report_ignored_repo(List.last(args), "#{Name.full(parts)}.run", issues, context)}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp report_ignored_repo({:fn, _meta, clauses}, trigger, issues, context) do
    clauses
    |> Enum.map(&repo_param/1)
    |> Enum.filter(&ignored?/1)
    |> Enum.reduce(issues, &[issue_for(context, &1, trigger) | &2])
  end

  defp report_ignored_repo(_callback, _trigger, issues, _context), do: issues

  defp repo_param({:->, _meta, [[{:when, _when_meta, [repo | _rest]}], _body]}), do: repo
  defp repo_param({:->, _meta, [[repo | _rest], _body]}), do: repo
  defp repo_param(_clause), do: nil

  defp ignored?({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: String.starts_with?(to_string(name), "_")

  defp ignored?(_pattern), do: false

  defp issue_for(context, {_name, meta, _context}, trigger) do
    format_issue(
      context.issue_meta,
      message: append_hint(@message, context.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
