defmodule Trogon.Credo.Check.Refactor.AnonymousFunction do
  use Credo.Check,
    base_priority: :low,
    category: :refactor,
    param_defaults: [
      max_clauses: 0,
      max_expressions: 0
    ],
    explanations: [
      check: """
      An anonymous function has no name, so nothing in the code says what it is
      for. A named function does, it can be documented and tested on its own,
      and it can be passed with a capture, which keeps the call site short.

      The code in this example ...

          Map.update(aliases, name, target, fn
            ^target -> target
            _other -> :ambiguous
          end)

      ... should be refactored to ...

          Map.update(aliases, name, target, &merge_target(&1, target))

          defp merge_target(target, target), do: target
          defp merge_target(_existing, _target), do: :ambiguous

      A capture is not reported, since it already names the function it calls.

      Both parameters count against a single anonymous function, which is
      reported when it exceeds either one. The defaults of `0` report every
      anonymous function, so relaxing this check is a matter of raising the
      limit that a project is willing to live with.

      An anonymous function written inside a `quote` block is reported, since a
      named function is still reachable from wherever the macro expands, as long
      as it is a public function of the module that defines the macro.
      """,
      params: [
        max_clauses: """
        The number of clauses an anonymous function may have. The default `0`
        reports every anonymous function, since every one of them has at least
        one clause. Set it to `1` to report only an anonymous function that
        pattern matches across several clauses.
        """,
        max_expressions: """
        The number of expressions the body of any one clause may have. The
        default `0` reports every anonymous function. Set it to `1` to allow a
        single expression body, or to `:infinity` to leave body size alone.
        """
      ]
    ]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    limits = %{
      max_clauses: Params.get(params, :max_clauses, __MODULE__),
      max_expressions: Params.get(params, :max_expressions, __MODULE__)
    }

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, limits))
  end

  defp traverse({:fn, meta, clauses} = ast, issues, issue_meta, limits) when is_list(clauses) do
    if over_limit?(clauses, limits) do
      {ast, [issue_for(issue_meta, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _limits), do: {ast, issues}

  defp over_limit?(clauses, limits) do
    over?(length(clauses), limits.max_clauses) or
      over?(widest_body(clauses), limits.max_expressions)
  end

  defp over?(_count, :infinity), do: false
  defp over?(count, limit), do: count > limit

  defp widest_body(clauses) do
    Enum.reduce(clauses, 0, &max(body_size(&1), &2))
  end

  defp body_size({:->, _meta, [_args, {:__block__, _, expressions}]}), do: length(expressions)
  defp body_size({:->, _meta, [_args, _expression]}), do: 1
  defp body_size(_clause), do: 0

  defp issue_for(issue_meta, meta) do
    format_issue(
      issue_meta,
      message: "Prefer a named function over an anonymous function.",
      trigger: "fn",
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
