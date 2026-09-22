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

      A qualified `Kernel.raise` or `Kernel.reraise` is reported the same way, since it
      is the same call written the long way. Aliases are resolved first, so a `Kernel`
      the file binds to another module is not read as the real one.

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

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @operations [:raise, :reraise]
  @sigils [:sigil_s, :sigil_S]
  @kernel_module "Kernel"

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

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, alias_meta, parts}, operation]}, _call_meta, [message | _rest]} = ast,
         issues,
         context
       )
       when operation in @operations do
    if ModuleName.resolve(parts, context.aliases) == @kernel_module do
      {ast, maybe_report(message, operation, "#{Name.full(parts)}.#{operation}", alias_meta, issues, context)}
    else
      {ast, issues}
    end
  end

  defp traverse({operation, meta, [message | _rest]} = ast, issues, context)
       when operation in @operations do
    {ast, maybe_report(message, operation, to_string(operation), meta, issues, context)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp maybe_report(message, operation, trigger, meta, issues, context) do
    if string?(message) do
      [issue_for(context, meta, operation, trigger) | issues]
    else
      issues
    end
  end

  defp string?(message) when is_binary(message), do: true
  defp string?({:<<>>, _meta, _parts}), do: true
  defp string?({sigil, _meta, _args}) when sigil in @sigils, do: true
  defp string?({:<>, _meta, _args}), do: true
  defp string?(_other), do: false

  defp issue_for(context, meta, operation, trigger) do
    format_issue(
      context.issue_meta,
      message: append_hint("A `#{operation}` must be given an exception, not a message string.", context.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
