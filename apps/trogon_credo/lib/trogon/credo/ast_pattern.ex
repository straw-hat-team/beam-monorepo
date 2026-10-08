defmodule Trogon.Credo.AstPattern do
  @moduledoc false

  # Rewrites an AST node that introduces a pattern so that only its expression
  # side is left for a prewalk to continue into, `{:ok, rewritten}`, or `:error`
  # for any other node, which a caller walks as it otherwise would.
  #
  # A clause head, a function head, a `with` or `for` generator, the left of a
  # match, and a `rescue` clause are all patterns, so what each of them binds is
  # dropped, keeping only the body or value a caller still needs to walk. A
  # `cond` condition and a `receive` timeout are expressions despite being
  # written to the left of a `->`, so both sides of those clauses are exposed
  # instead of having their left side dropped.

  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  def hide_pattern_position({:cond, meta, [blocks]}) when is_list(blocks) do
    {:ok, {:cond, meta, [expose_clauses(blocks, :do)]}}
  end

  def hide_pattern_position({:receive, meta, [blocks]}) when is_list(blocks) do
    {:ok, {:receive, meta, [expose_clauses(blocks, :after)]}}
  end

  def hide_pattern_position({:->, _meta, [_pattern, body]}), do: {:ok, body}

  def hide_pattern_position({operator, _meta, [_pattern, value]}) when operator in [:=, :<-] do
    {:ok, value}
  end

  def hide_pattern_position({kind, _meta, [{:when, _meta2, [_head, _guard]} | rest]})
      when kind in @definition_kinds do
    {:ok, rest}
  end

  def hide_pattern_position({kind, _meta, [_head | rest]}) when kind in @definition_kinds do
    {:ok, rest}
  end

  def hide_pattern_position(_ast), do: :error

  defp expose_clauses(blocks, key) do
    Enum.map(blocks, &expose_block(&1, key))
  end

  defp expose_block({key, clauses}, key) when is_list(clauses) do
    {key, Enum.map(clauses, &expose_clause/1)}
  end

  defp expose_block(block, _key), do: block

  defp expose_clause({:->, meta, args}), do: {:__block__, meta, args}
  defp expose_clause(clause), do: clause
end
