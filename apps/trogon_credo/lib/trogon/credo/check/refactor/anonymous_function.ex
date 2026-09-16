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

      A capture that names a function, `&merge_target/2` or
      `&merge_target(&1, target)`, is not reported, since the name is right
      there. A capture that names none, `& &1.id` or `&(&1 * 2)`, is reported
      like any other anonymous function, otherwise writing
      `fn item -> item.id end` as `& &1.id` would be enough to silence this
      check without naming anything.

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

  @function_name ~r/^[a-z]/

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
    report_if_over_limit(ast, issues, issue_meta, meta, length(clauses), widest_body(clauses), limits)
  end

  defp traverse({:&, _meta, [position]} = ast, issues, _issue_meta, _limits)
       when is_integer(position) do
    {ast, issues}
  end

  defp traverse({:&, meta, [body]} = ast, issues, issue_meta, limits) do
    if names_function?(body) do
      {ast, issues}
    else
      report_if_over_limit(ast, issues, issue_meta, meta, 1, expressions(body), limits)
    end
  end

  defp traverse(ast, issues, _issue_meta, _limits), do: {ast, issues}

  defp report_if_over_limit(ast, issues, issue_meta, meta, clauses, expressions, limits) do
    if over?(clauses, limits.max_clauses) or over?(expressions, limits.max_expressions) do
      {ast, [issue_for(issue_meta, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp names_function?({:/, _meta, [{name, _, nil}, arity]})
       when is_atom(name) and is_integer(arity) do
    true
  end

  defp names_function?({:/, _meta, [{{:., _, [_module, name]}, _, []}, arity]})
       when is_atom(name) and is_integer(arity) do
    true
  end

  defp names_function?({{:., _meta, [{:&, _, _position}, _name]}, _, _args}), do: false

  defp names_function?({{:., _meta, [_module, name]}, _, args})
       when is_atom(name) and is_list(args) do
    true
  end

  defp names_function?({name, _meta, args}) when is_atom(name) and is_list(args) do
    not Macro.operator?(name, length(args)) and
      Regex.match?(@function_name, Atom.to_string(name))
  end

  defp names_function?(_body), do: false

  defp over?(_count, :infinity), do: false
  defp over?(count, limit), do: count > limit

  defp widest_body(clauses) do
    Enum.reduce(clauses, 0, &max(body_size(&1), &2))
  end

  defp body_size({:->, _meta, [_args, body]}), do: expressions(body)
  defp body_size(_clause), do: 0

  defp expressions({:__block__, _meta, expressions}), do: length(expressions)
  defp expressions(_body), do: 1

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
