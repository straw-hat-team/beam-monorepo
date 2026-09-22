defmodule Trogon.Credo.MixDeps do
  @moduledoc false

  alias Credo.SourceFile

  @block_keys [:do, :else, :after, :catch, :rescue]

  # The dependency names a `mix.exs` declares, each with the line it is written
  # on.
  #
  # Only the body of a `deps/0` function is read, so a Mix alias or any other
  # keyword list that happens to look like a dependency list is left alone. A
  # dependency whose name is not written as a literal atom cannot be read
  # statically and is not returned.
  def names(source_file) do
    source_file
    |> Credo.Code.prewalk(&traverse/2, [])
    |> Enum.reverse()
    |> Enum.map(fn {name, line} -> {name, line || line(source_file, name)} end)
  end

  # The line a dependency is written on, read from the source text, for the two
  # element tuple form that the parser gives no line of its own.
  def line(source_file, dep) do
    pattern = ~r/\{\s*:#{Regex.escape(to_string(dep))}\s*,/

    source_file
    |> SourceFile.lines()
    |> Enum.find_value(fn {line_no, text} -> Regex.match?(pattern, text) && line_no end)
    |> case do
      nil -> 1
      line_no -> line_no
    end
  end

  defp traverse({definition, _meta, [{:deps, _, args}, [do: body]]}, names)
       when definition in [:def, :defp] and (is_nil(args) or args == []) do
    {[], deps_list(body, names)}
  end

  defp traverse(ast, names), do: {ast, names}

  # Manual recursion (rather than a second `Credo.Code.prewalk/3`) so that only
  # what the body of `deps/0` evaluates to is read. A dependency and one of its
  # own options are written the same way, as a tuple of an atom and a value, so
  # only their place in the source tells them apart, and an expression is read
  # for dependencies only where the list itself belongs.
  defp deps_list(list, names) when is_list(list), do: Enum.reduce(list, names, &entry/2)

  # A block evaluates to its last expression, and a list built from several is
  # read through each of its parts.
  defp deps_list({:__block__, _meta, exprs}, names), do: deps_list(List.last(exprs), names)
  defp deps_list({:++, _meta, parts}, names), do: Enum.reduce(parts, names, &deps_list/2)

  # Any other expression is read through the blocks it carries, which is how the
  # branches of a conditional are reached. Nothing else in it is read, since a
  # keyword written elsewhere in the body is not a dependency.
  defp deps_list({_form, _meta, args}, names) when is_list(args) do
    args |> Enum.flat_map(&blocks/1) |> Enum.reduce(names, &deps_list/2)
  end

  defp deps_list(_ast, names), do: names

  defp blocks(list) when is_list(list) do
    for {key, body} <- list, key in @block_keys, do: body
  end

  defp blocks(_ast), do: []

  # Neither a requirement nor the options are read, since only the name decides
  # what this module reports, and a project may state either through a module
  # attribute or a call.
  defp entry({dep, _requirement}, names) when is_atom(dep), do: [{dep, nil} | names]

  defp entry({:{}, meta, [dep, _requirement, _opts]}, names) when is_atom(dep) do
    [{dep, meta[:line]} | names]
  end

  # A clause of a conditional evaluates to a list of its own.
  defp entry({:->, _meta, [_pattern, body]}, names), do: deps_list(body, names)

  # A dependency whose name is not written as a literal atom cannot be read, and
  # nothing inside such an entry is read either.
  defp entry(_ast, names), do: names
end
