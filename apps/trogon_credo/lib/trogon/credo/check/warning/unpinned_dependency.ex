defmodule Trogon.Credo.Check.Warning.UnpinnedDependency do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [deps: []],
    explanations: [
      check: """
      Dependencies that are not pinned to an immutable reference can change
      the code that ships in a build without a corresponding change in your
      lockfile review, which makes supply chain attacks and accidental
      regressions harder to catch.

      A dependency is considered pinned when it is either a git dependency
      pointing at a full 40 character commit sha through `ref:`, or a hex
      dependency whose requirement is an exact version, such as `"1.2.3"`.

      Dependencies pinned with `branch:`, `tag:`, an operator requirement such
      as `"~> 1.2.0"`, or no `ref:` at all are reported.

      Only the body of a `deps/0` function inside `mix.exs` is analyzed, so a
      Mix alias or any other keyword list that happens to share a name with a
      configured dependency is left alone. A `ref:` that is not a literal
      string, a module attribute for instance, cannot be read statically and is
      not reported.
      """,
      params: [
        deps: "List of dependency names (atoms) or `{:dep, \"Custom message\"}` tuples that must be pinned."
      ]
    ]

  alias Credo.SourceFile

  @full_sha ~r/^[0-9a-f]{40}$/
  @exact_version ~r/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/

  @doc false
  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if Path.basename(filename) == "mix.exs" do
      deps = prepare_deps(Params.get(params, :deps, __MODULE__))
      issue_meta = IssueMeta.for(source_file, params)

      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, deps))
    else
      []
    end
  end

  defp traverse({definition, _meta, [{:deps, _, args}, [do: body]]}, issues, issue_meta, deps)
       when definition in [:def, :defp] and (is_nil(args) or args == []) do
    {[], walk(body, issues, issue_meta, deps)}
  end

  defp traverse(ast, issues, _issue_meta, _deps), do: {ast, issues}

  # Manual recursion (rather than a second `Credo.Code.prewalk/3`) so that only
  # the body of `deps/0` is inspected for dependency tuples.
  defp walk({dep, spec}, issues, issue_meta, deps)
       when is_atom(dep) and (is_binary(spec) or is_list(spec)) do
    check_dep(dep, nil, fn -> check_spec(dep, spec) end, issues, issue_meta, deps)
  end

  defp walk({:{}, meta, [dep, requirement, opts]}, issues, issue_meta, deps)
       when is_atom(dep) and is_list(opts) do
    check_dep(dep, meta[:line], fn -> check_tuple(dep, requirement, opts) end, issues, issue_meta, deps)
  end

  defp walk({_, _, args}, issues, issue_meta, deps) when is_list(args) do
    walk(args, issues, issue_meta, deps)
  end

  defp walk({left, right}, issues, issue_meta, deps) do
    walk(right, walk(left, issues, issue_meta, deps), issue_meta, deps)
  end

  defp walk(list, issues, issue_meta, deps) when is_list(list) do
    Enum.reduce(list, issues, fn item, acc -> walk(item, acc, issue_meta, deps) end)
  end

  defp walk(_ast, issues, _issue_meta, _deps), do: issues

  defp check_dep(dep, line_no, check, issues, issue_meta, deps) do
    with {:ok, message} <- Map.fetch(deps, dep),
         {:error, reason} <- check.() do
      [issue_for(issue_meta, line_no, dep, message, reason) | issues]
    else
      _ -> issues
    end
  end

  defp check_spec(dep, opts) when is_list(opts) do
    if git_opts?(opts) do
      check_git_opts(opts)
    else
      {:error, "declare a hex requirement for `#{dep}` and pin it to an exact version"}
    end
  end

  defp check_spec(_dep, requirement) when is_binary(requirement) do
    check_hex_requirement(requirement)
  end

  defp check_tuple(dep, requirement, opts) do
    if git_opts?(opts) do
      check_git_opts(opts)
    else
      check_hex_requirement(requirement, dep)
    end
  end

  defp git_opts?(opts) do
    Keyword.has_key?(opts, :git) or Keyword.has_key?(opts, :github)
  end

  defp check_git_opts(opts) do
    case Keyword.fetch(opts, :ref) do
      {:ok, ref} when is_binary(ref) ->
        if Regex.match?(@full_sha, ref) do
          :ok
        else
          {:error, "use a full 40 character commit sha in `ref:` instead of `#{ref}`"}
        end

      {:ok, _ref} ->
        :ok

      :error ->
        cond do
          Keyword.has_key?(opts, :branch) ->
            {:error, "replace `branch:` with `ref:` pinned to a full 40 character commit sha"}

          Keyword.has_key?(opts, :tag) ->
            {:error, "replace `tag:` with `ref:` pinned to a full 40 character commit sha"}

          true ->
            {:error, "add `ref:` pinned to a full 40 character commit sha"}
        end
    end
  end

  defp check_hex_requirement(requirement, dep \\ nil)

  defp check_hex_requirement(requirement, _dep) when is_binary(requirement) do
    if Regex.match?(@exact_version, requirement) do
      :ok
    else
      {:error, "use an exact version instead of `#{requirement}`"}
    end
  end

  defp check_hex_requirement(_requirement, dep) do
    {:error, "declare a hex requirement for `#{dep}` and pin it to an exact version"}
  end

  defp issue_for(issue_meta, line_no, dep, message, reason) do
    message_text =
      if message do
        "#{message} (#{reason})"
      else
        "Dependency `#{dep}` must be pinned: #{reason}."
      end

    format_issue(
      issue_meta,
      message: message_text,
      trigger: to_string(dep),
      line_no: line_no || line_for_dep(issue_meta, dep)
    )
  end

  defp line_for_dep(issue_meta, dep) do
    source_file = IssueMeta.source_file(issue_meta)
    pattern = ~r/\{\s*:#{Regex.escape(to_string(dep))}\s*,/

    source_file
    |> SourceFile.lines()
    |> Enum.find_value(fn {line_no, text} -> Regex.match?(pattern, text) && line_no end)
    |> case do
      nil -> 1
      line_no -> line_no
    end
  end

  defp prepare_deps(deps) do
    deps
    |> Enum.map(fn
      {dep, message} -> {dep, message}
      dep -> {dep, nil}
    end)
    |> Map.new()
  end
end
