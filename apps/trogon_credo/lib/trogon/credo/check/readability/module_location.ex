defmodule Trogon.Credo.Check.Readability.ModuleLocation do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [],
      path_segment: nil,
      namespace_segment: nil
    ],
    explanations: [
      check: """
      Modules that `use` a given module often belong to an architectural
      layer that is expected to live in one place. This check enforces that
      such modules sit under an expected directory and inside an expected
      namespace segment.

          {Trogon.Credo.Check.Readability.ModuleLocation,
           [for_use: [Oban.Worker], path_segment: "jobs", namespace_segment: :Jobs]}

      With the configuration above, a module that uses `Oban.Worker` is
      expected to live under a `jobs/` directory and inside a namespace
      containing the `Jobs` segment.

      Moving or renaming a module that is referenced by persisted data, a
      background job row naming its worker module, for instance, may need a
      data migration or an alias, so the rename is not always free.

      Code inside a `quote` block is not analyzed, since a module defined
      there, or a `use` written there, belongs to wherever the macro expands
      rather than to the module that defines the macro.

      A module whose namespace carries a segment that is only known at compile
      time, `defmodule __MODULE__.Child` for instance, is still checked against
      `path_segment`, but not against `namespace_segment`, since the namespace
      it ends up in cannot be read statically.

      A `defmodule` whose name is not written as an alias, `defmodule :worker`
      or `defmodule Module.concat(Foo, Bar)` for instance, does not nest inside
      the namespace of the module it is written in, and is treated accordingly.
      """,
      params: [
        for_use: """
        A list of modules. This check only applies to modules that `use` one
        of these modules. The default empty list makes the check inert,
        since there is no universal expected location. A `use` written with an
        explicit `Elixir.` prefix names the same module.
        """,
        path_segment: """
        A single directory name that a matching module's file is expected to
        live under. Skipped when set to `nil`, the default.
        """,
        namespace_segment: """
        A single module name segment, given as an atom or a string, that is
        expected to appear anywhere in a matching module's namespace. Skipped
        when set to `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    for_use = Params.get(params, :for_use, __MODULE__)

    if for_use == [] do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        for_use: Enum.map(for_use, &ModuleName.full/1),
        path_segment: Params.get(params, :path_segment, __MODULE__),
        namespace_segment: normalize_segment(Params.get(params, :namespace_segment, __MODULE__)),
        aliases: ModuleName.collect_aliases(source_file)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    end
  end

  defp normalize_segment(nil), do: nil
  defp normalize_segment(segment), do: to_string(segment)

  defp traverse({:defmodule, _meta, [{:__aliases__, _, parts} | rest]}, issues, context) do
    {[], walk(rest, parts, issues, context)}
  end

  defp traverse({:defmodule, _meta, [name | rest]}, issues, context) do
    {[], walk(rest, [name], issues, context)}
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse(ast, issues, _context), do: {ast, issues}

  # Manual recursion (mirroring `traverse/3` above) so that a nested
  # `defmodule` extends the namespace of the enclosing one and a `use` site is
  # attributed to its enclosing module's fully qualified name.
  defp walk({:defmodule, _meta, [{:__aliases__, _, parts} | rest]}, namespace, issues, context) do
    walk(rest, namespace ++ parts, issues, context)
  end

  defp walk({:defmodule, _meta, [name | rest]}, _namespace, issues, context) do
    walk(rest, [name], issues, context)
  end

  defp walk({:use, _meta, [{:__aliases__, meta, used_parts} | _]}, namespace, issues, context) do
    if used_module?(context, used_parts) do
      check_location(namespace, used_parts, meta, issues, context)
    else
      issues
    end
  end

  defp walk({:quote, _meta, _args}, _namespace, issues, _context), do: issues

  defp walk({_, _, args}, namespace, issues, context) when is_list(args) do
    walk(args, namespace, issues, context)
  end

  defp walk({left, right}, namespace, issues, context) do
    walk(right, namespace, walk(left, namespace, issues, context), context)
  end

  defp walk(list, namespace, issues, context) when is_list(list) do
    Enum.reduce(list, issues, fn item, acc -> walk(item, namespace, acc, context) end)
  end

  defp walk(_ast, _namespace, issues, _context), do: issues

  defp used_module?(context, used_parts) do
    ModuleName.resolve(used_parts, context.aliases) in context.for_use
  end

  defp check_location(namespace, used_parts, meta, issues, context) do
    %{
      issue_meta: issue_meta,
      path_segment: path_segment,
      namespace_segment: namespace_segment
    } = context

    used_module = Name.full(used_parts)

    cond do
      path_segment != nil and not path_compliant?(issue_meta, path_segment) ->
        [path_issue(issue_meta, meta, used_module, path_segment) | issues]

      namespace_segment != nil and readable_namespace?(namespace) and
          not namespace_compliant?(namespace, namespace_segment) ->
        [namespace_issue(issue_meta, meta, used_module, namespace_segment) | issues]

      true ->
        issues
    end
  end

  defp path_compliant?(issue_meta, path_segment) do
    source_file = IssueMeta.source_file(issue_meta)

    source_file.filename
    |> Path.split()
    |> Enum.member?(path_segment)
  end

  defp readable_namespace?(namespace), do: Enum.all?(namespace, &is_atom/1)

  defp namespace_compliant?(namespace, namespace_segment) do
    Enum.any?(namespace, fn part -> to_string(part) == namespace_segment end)
  end

  defp path_issue(issue_meta, meta, used_module, path_segment) do
    format_issue(
      issue_meta,
      message: "Modules that use `#{used_module}` must live under a `#{path_segment}/` directory.",
      trigger: used_module,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp namespace_issue(issue_meta, meta, used_module, namespace_segment) do
    format_issue(
      issue_meta,
      message: "Modules that use `#{used_module}` must be in a namespace containing `#{namespace_segment}`.",
      trigger: used_module,
      line_no: meta[:line],
      column: meta[:column]
    )
  end
end
