defmodule Trogon.Credo.Aliases do
  @moduledoc false

  alias Credo.Code.Name

  def collect(source_file) do
    Credo.Code.prewalk(source_file, &traverse/2, %{})
  end

  def resolve([first | rest], aliases) do
    case Map.fetch(aliases, to_string(first)) do
      {:ok, resolved_head} -> Name.full([resolved_head | rest])
      :error -> Name.full([first | rest])
    end
  end

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}, opts]}, aliases)
       when is_list(opts) do
    case Keyword.fetch(opts, :as) do
      {:ok, {:__aliases__, _, as_parts}} ->
        {[], Map.put(aliases, Name.full(as_parts), Name.full(parts))}

      _ ->
        {[], put_default(aliases, parts)}
    end
  end

  defp traverse(
         {:alias, _meta, [{{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, alias_nodes}]},
         aliases
       ) do
    new_aliases =
      Enum.reduce(alias_nodes, aliases, fn {:__aliases__, _, member_parts}, acc ->
        put_default(acc, base_parts ++ member_parts)
      end)

    {[], new_aliases}
  end

  defp traverse({:alias, _meta, [{:__aliases__, _, parts}]}, aliases) do
    {[], put_default(aliases, parts)}
  end

  defp traverse(ast, aliases), do: {ast, aliases}

  defp put_default(aliases, parts) do
    Map.put(aliases, Name.last(parts), Name.full(parts))
  end
end
