defmodule Trogon.Credo.Check.Warning.RaiseString do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [hint: nil],
    explanations: [
      check: """
      `raise "something went wrong"` raises a `RuntimeError` whose only content is
      prose. Nothing downstream can match on it, a caller cannot rescue one failure
      and let another propagate, and the message cannot carry fields for a log line or
      an API response. Name an exception module instead:

          raise MyApp.NotFoundError
          raise MyApp.NotFoundError, id: id
          raise %MyApp.Error{}

      Reported: a string literal, an interpolation, a `~s` or `~S` sigil, or a `<>`
      concatenation, given to `raise` or to `reraise`.

          raise "boom"
          raise "no user \#{id}"
          raise "no user " <> id
          raise ~s(boom)

      Not reported: a `raise` given a variable, a function call, or a module attribute,
      `raise exception` for instance, since the check cannot know what a variable
      holds. This is the check's main blind spot, and a project that wants the rule
      airtight keeps the raise site readable rather than hiding the message behind a
      variable.

      A `raise` inside a `quote` block is reported, since the macro injects it into
      every module that expands it. A `raise` injected by a library's `__using__` macro
      lives in that library's source and is invisible here, so this check needs no
      exclusion list for framework macros.

      Credo's `Credo.Check.Warning.RaiseInsideRescue` is a different rule: it is about
      a `raise` inside a `rescue` discarding the stacktrace, regardless of the
      argument, where this check is about the argument regardless of location.
      """,
      params: [
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  @operations [:raise, :reraise]
  @sigils [:sigil_s, :sigil_S]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    hint = Params.get(params, :hint, __MODULE__)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, hint))
  end

  defp traverse({operation, meta, [message | _rest]} = ast, issues, issue_meta, hint)
       when operation in @operations do
    if string?(message) do
      {ast, [issue_for(issue_meta, meta, operation, hint) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _hint), do: {ast, issues}

  defp string?(message) when is_binary(message), do: true
  defp string?({:<<>>, _meta, _parts}), do: true
  defp string?({sigil, _meta, _args}) when sigil in @sigils, do: true
  defp string?({:<>, _meta, _args}), do: true
  defp string?(_other), do: false

  defp issue_for(issue_meta, meta, operation, hint) do
    format_issue(
      issue_meta,
      message: append_hint("A `#{operation}` must be given an exception, not a message string.", hint),
      trigger: to_string(operation),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
