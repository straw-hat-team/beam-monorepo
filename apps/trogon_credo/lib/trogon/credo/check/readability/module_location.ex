defmodule Trogon.Credo.Check.Readability.ModuleLocation do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      for_use: [],
      path_segment: nil,
      namespace_segment: nil,
      hint: nil
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

      `path_segment` and `namespace_segment` each accept a single value or a
      list of values, a list meaning a module satisfies the check as long as
      it matches any one of them. `namespace_segment` also accepts a
      `{segment, position}` tuple that pins the segment to a specific place
      in the namespace, counting from the root when `position` is positive
      and from the end when negative.

          {Trogon.Credo.Check.Readability.ModuleLocation,
           [for_use: [Oban.Worker],
            path_segment: ["jobs", "workers"],
            namespace_segment: [:Jobs, {:Processor, 3}]]}

      With the configuration above, a module that uses `Oban.Worker` is
      expected to live under a `jobs/` or `workers/` directory, and inside a
      namespace that either contains the `Jobs` segment or carries
      `Processor` as its third segment.

      A position that falls outside the namespace never matches, so
      `{:Jobs, 4}` never matches a three segment namespace.

      A position counts over every segment of the module name, including the
      last one, which names the module itself rather than a namespace it sits
      in. `MyApp.Jobs.SendEmail` has three segments, so `{:Jobs, 2}` and
      `{:Jobs, -2}` both match it while `{:Jobs, -1}` does not, since the last
      segment is `SendEmail`.

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
        A single directory name, or a list of directory names, that a
        matching module's file is expected to live under. A list means the
        module's file may live under any one of the directories. Skipped
        when set to `nil`, the default, or to an empty list.
        """,
        namespace_segment: """
        A single module name segment, given as an atom or a string, that is
        expected to appear anywhere in a matching module's namespace. It can
        also be given as `{segment, position}`, where `position` is a
        non-zero integer, counting from the root of the namespace when
        positive and from the end when negative, so `{:Jobs, 2}` requires
        the second segment to be `Jobs` and `{:Jobs, -1}` requires the last
        segment to be `Jobs`. The count covers every segment of the module
        name, the last one included, which names the module itself rather
        than a namespace it sits in. A list of any of these forms
        means satisfying any one of them is enough. Skipped when set to `nil`,
        the default, or to an empty list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
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
        path_segment: normalize_path_segments(Params.get(params, :path_segment, __MODULE__)),
        namespace_segment: normalize_namespace_segments(Params.get(params, :namespace_segment, __MODULE__)),
        hint: Params.get(params, :hint, __MODULE__),
        aliases: ModuleName.collect_aliases(source_file)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    end
  end

  defp normalize_path_segments(nil), do: nil
  defp normalize_path_segments([]), do: nil
  defp normalize_path_segments(segments) when is_list(segments), do: Enum.map(segments, &to_string/1)
  defp normalize_path_segments(segment), do: [to_string(segment)]

  defp normalize_namespace_segments(nil), do: nil
  defp normalize_namespace_segments([]), do: nil

  defp normalize_namespace_segments(segments) when is_list(segments),
    do: Enum.map(segments, &normalize_namespace_rule/1)

  defp normalize_namespace_segments(segment), do: [normalize_namespace_rule(segment)]

  defp normalize_namespace_rule({segment, position}) when is_integer(position) and position != 0 do
    {to_string(segment), position}
  end

  defp normalize_namespace_rule({_segment, position} = rule) do
    raise ArgumentError,
          "invalid namespace_segment #{inspect(rule)}: position must be a non-zero integer, got: #{inspect(position)}"
  end

  defp normalize_namespace_rule(segment), do: {to_string(segment), nil}

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
      namespace_segment: namespace_segment,
      hint: hint
    } = context

    used_module = Name.full(used_parts)

    cond do
      path_segment != nil and not path_compliant?(issue_meta, path_segment) ->
        [path_issue(issue_meta, meta, used_module, path_segment, hint) | issues]

      namespace_segment != nil and readable_namespace?(namespace) and
          not namespace_compliant?(namespace, namespace_segment) ->
        [namespace_issue(issue_meta, meta, used_module, namespace_segment, hint) | issues]

      true ->
        issues
    end
  end

  defp path_compliant?(issue_meta, path_segment) do
    source_file = IssueMeta.source_file(issue_meta)
    parts = Path.split(source_file.filename)

    Enum.any?(path_segment, &Enum.member?(parts, &1))
  end

  defp readable_namespace?(namespace), do: Enum.all?(namespace, &is_atom/1)

  defp namespace_compliant?(namespace, namespace_segment) do
    Enum.any?(namespace_segment, &namespace_rule_compliant?(namespace, &1))
  end

  defp namespace_rule_compliant?(namespace, {segment, nil}) do
    Enum.any?(namespace, fn part -> to_string(part) == segment end)
  end

  defp namespace_rule_compliant?(namespace, {segment, position}) do
    case Enum.at(namespace, position_index(position)) do
      nil -> false
      part -> to_string(part) == segment
    end
  end

  defp position_index(position) when position > 0, do: position - 1
  defp position_index(position) when position < 0, do: position

  defp path_issue(issue_meta, meta, used_module, path_segment, hint) do
    format_issue(
      issue_meta,
      message: path_segment |> path_message(used_module) |> append_hint(hint),
      trigger: used_module,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp path_message([segment], used_module) do
    "Modules that use `#{used_module}` must live under a `#{segment}/` directory."
  end

  defp path_message(segments, used_module) do
    directories = Enum.map_join(segments, ", ", &"`#{&1}/`")
    "Modules that use `#{used_module}` must live under one of these directories: #{directories}."
  end

  defp namespace_issue(issue_meta, meta, used_module, namespace_segment, hint) do
    format_issue(
      issue_meta,
      message: namespace_segment |> namespace_message(used_module) |> append_hint(hint),
      trigger: used_module,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp namespace_message(namespace_segment, used_module) do
    descriptions = Enum.map(namespace_segment, &namespace_rule_description/1)

    "Modules that use `#{used_module}` must be in a namespace " <>
      Enum.join(descriptions, ", or a namespace ") <> "."
  end

  defp namespace_rule_description({segment, nil}), do: "containing `#{segment}`"
  defp namespace_rule_description({segment, position}) when position > 0, do: "with `#{segment}` as segment #{position}"

  defp namespace_rule_description({segment, position}) when position < 0 do
    "with `#{segment}` as segment #{-position} counting from the end"
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
