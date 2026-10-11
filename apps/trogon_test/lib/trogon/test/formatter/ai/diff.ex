defmodule Trogon.Test.Formatter.AI.Diff do
  @moduledoc false

  @type side :: {:value, term()} | :missing
  @type change :: {path :: [term()], left :: side(), right :: side()}

  # Walks into maps by key, and into lists and tuples of the same length by
  # position. A list of another length is one change, since every position after
  # an insertion would differ.
  @spec changes(term(), term(), (term(), term() -> boolean())) :: [change()]
  def changes(left, right, equal?), do: changes(left, right, equal?, [])

  defp changes(%struct{} = left, %struct{} = right, equal?, path) do
    map_changes(Map.from_struct(left), Map.from_struct(right), equal?, path)
  end

  defp changes(left, right, equal?, path)
       when is_map(left) and is_map(right) and not is_struct(left) and not is_struct(right) do
    map_changes(left, right, equal?, path)
  end

  defp changes(left, right, equal?, path)
       when is_list(left) and is_list(right) and length(left) == length(right) do
    left |> Enum.zip(right) |> positional_changes(equal?, path)
  end

  defp changes(left, right, equal?, path)
       when is_tuple(left) and is_tuple(right) and tuple_size(left) == tuple_size(right) do
    left |> Tuple.to_list() |> Enum.zip(Tuple.to_list(right)) |> positional_changes(equal?, path)
  end

  defp changes(left, right, equal?, path) do
    if equal?.(left, right), do: [], else: [{Enum.reverse(path), {:value, left}, {:value, right}}]
  end

  defp map_changes(left, right, equal?, path) do
    (Map.keys(left) ++ Map.keys(right))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(&key_changes(Map.fetch(left, &1), Map.fetch(right, &1), equal?, [&1 | path]))
  end

  defp key_changes({:ok, left}, {:ok, right}, equal?, path), do: changes(left, right, equal?, path)
  defp key_changes({:ok, left}, :error, _equal?, path), do: [{Enum.reverse(path), {:value, left}, :missing}]
  defp key_changes(:error, {:ok, right}, _equal?, path), do: [{Enum.reverse(path), :missing, {:value, right}}]

  defp positional_changes(pairs, equal?, path) do
    pairs
    |> Enum.with_index()
    |> Enum.flat_map(&position_changes(&1, equal?, path))
  end

  defp position_changes({{left, right}, index}, equal?, path), do: changes(left, right, equal?, [index | path])
end
