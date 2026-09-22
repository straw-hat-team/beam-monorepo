defmodule Trogon.Credo.Check.Design.ModuleCardinality do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    run_on_all: true,
    param_defaults: [
      required: [],
      unique: [],
      hint: nil
    ],
    explanations: [
      check: """
      Some conventions are about a module that is missing, or about a second module that
      should not exist: a project that must define the one module its release calls, a
      namespace where exactly one module may configure a client everything else goes
      through. A check that reads one file at a time cannot see either. Absence is not
      written anywhere, and a duplicate is only visible once the other file has been
      read too.

      This check reads the whole analyzed set at once, and counts the modules matching
      each pattern it is given.

          # the project must define the module its release calls
          {Trogon.Credo.Check.Design.ModuleCardinality,
           [required: ["Acme.Release"]]}

          # one module, and only one, configures the HTTP client
          {Trogon.Credo.Check.Design.ModuleCardinality,
           [required: ["Acme.**.HttpClient"],
            unique: ["Acme.**.HttpClient"]]}

      `required` says at least one module matches, and `unique` says at most one does.
      Setting both, as in the second example, says exactly one.

      A pattern is matched against the fully qualified name of every module the analyzed
      files define, using the syntax
      `Trogon.Credo.Check.Design.NamespaceBoundary` documents. A module nested in
      another is named under the module that encloses it, so a `defmodule Worker`
      written inside `defmodule Acme` counts as `Acme.Worker`.

      A `required` pattern that nothing matches is a statement about the project rather
      than about a file, so its issue is reported at the top of the first file analyzed,
      by name, which keeps the report in the same place from one run to the next. A
      `unique` pattern that too many modules match reports each match after the first,
      at the `defmodule` that defines it, so the issue sits on the module that is one too
      many rather than on the one that was there first.

      What counts is what the analyzed set defines, so Credo's own `files:` param scopes
      the rule: a `required` pattern naming a module that lives in a file the
      configuration excludes is reported as missing. A module defined inside a `quote`
      block is not counted, since it belongs to wherever the macro expands, and neither
      is a module whose name is not written as a plain alias, `__MODULE__.Child` for
      instance, along with anything nested inside it, since the name it defines is only
      known at compile time.

      This check counts definitions, so it says nothing about whether a module is
      reachable, used, or correct. A module that exists to satisfy a `required` pattern
      and does nothing satisfies it.
      """,
      params: [
        required: """
        A pattern, or a list of patterns, that at least one module must match. An entry
        may also be given as a `{pattern, "message"}` tuple carrying its own message. The
        default empty list makes this half of the check inert, since there is no module
        every project must define.
        """,
        unique: """
        A pattern, or a list of patterns, that at most one module may match. An entry may
        also be given as a `{pattern, "message"}` tuple carrying its own message. The
        default empty list makes this half of the check inert.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a project
        can say in its own words what to do instead. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @doc false
  @impl true
  def run_on_all_source_files(exec, source_files, params) do
    required = prepare(Params.get(params, :required, __MODULE__) || [], :required)
    unique = prepare(Params.get(params, :unique, __MODULE__) || [], :unique)

    if required == [] and unique == [] do
      :ok
    else
      analyze(exec, source_files, params, required, unique)
    end
  end

  defp analyze(exec, source_files, params, required, unique) do
    context = %{
      params: params,
      hint: Params.get(params, :hint, __MODULE__),
      source_files: Enum.sort_by(source_files, & &1.filename)
    }

    modules = Enum.flat_map(context.source_files, &modules/1)

    issues =
      Enum.flat_map(required, &required_issues(&1, modules, context)) ++
        Enum.flat_map(unique, &unique_issues(&1, modules, context))

    append_issues_and_timings(issues, exec)

    :ok
  end

  defp required_issues(entry, modules, context) do
    if Enum.any?(modules, &matches?(entry, &1)) do
      []
    else
      Enum.map(Enum.take(context.source_files, 1), &project_issue(&1, entry, context))
    end
  end

  defp unique_issues(entry, modules, context) do
    case Enum.filter(modules, &matches?(entry, &1)) do
      [kept | [_ | _] = rest] -> Enum.map(rest, &module_issue(&1, kept, entry, context))
      _matches -> []
    end
  end

  defp matches?({regex, _pattern, _message}, module), do: Regex.match?(regex, module.name)

  defp project_issue(source_file, {_regex, pattern, message}, context) do
    format_issue(
      IssueMeta.for(source_file, context.params),
      message: append_hint(message || missing_message(pattern), context.hint),
      trigger: pattern,
      line_no: 1
    )
  end

  defp module_issue(module, kept, {_regex, pattern, message}, context) do
    format_issue(
      IssueMeta.for(module.source_file, context.params),
      message: append_hint(message || duplicate_message(pattern, kept), context.hint),
      trigger: module.name,
      line_no: module.meta[:line],
      column: module.meta[:column]
    )
  end

  defp missing_message(pattern), do: "No module matches `#{pattern}`, which this project requires."

  defp duplicate_message(pattern, kept) do
    "Only one module may match `#{pattern}`, which `#{kept.name}` already does."
  end

  defp modules(source_file) do
    source_file
    |> SourceFile.ast()
    |> collect([], [])
    |> Enum.reverse()
    |> Enum.map(fn {name, meta} -> %{name: name, meta: meta, source_file: source_file} end)
  end

  # Manual recursion (rather than `Credo.Code.prewalk/3`) so that a nested module
  # is named under the module that encloses it.
  defp collect({:defmodule, _meta, [{:__aliases__, meta, parts}, body]}, prefix, modules) do
    if Enum.all?(parts, &is_atom/1) do
      nested_prefix = prefix ++ parts

      collect(body, nested_prefix, [{ModuleName.full(nested_prefix), meta} | modules])
    else
      modules
    end
  end

  defp collect({:defmodule, _meta, [_name, _body]}, _prefix, modules), do: modules
  defp collect({:quote, _meta, _args}, _prefix, modules), do: modules

  defp collect({_form, _meta, args}, prefix, modules) when is_list(args) do
    collect(args, prefix, modules)
  end

  defp collect({left, right}, prefix, modules) do
    collect(right, prefix, collect(left, prefix, modules))
  end

  defp collect(list, prefix, modules) when is_list(list) do
    Enum.reduce(list, modules, &collect(&1, prefix, &2))
  end

  defp collect(_ast, _prefix, modules), do: modules

  defp prepare(entries, param) when is_list(entries), do: Enum.map(entries, &normalize(&1, param))
  defp prepare(entry, param), do: [normalize(entry, param)]

  defp normalize({pattern, message}, param) when is_binary(message) do
    {compile!(pattern, param), text(pattern, param), message}
  end

  defp normalize(pattern, param) when is_binary(pattern) or is_atom(pattern) do
    {compile!(pattern, param), text(pattern, param), nil}
  end

  defp normalize(entry, param), do: raise_invalid(entry, param)

  defp compile!(pattern, param) do
    case ModulePattern.compile(pattern) do
      {:ok, regex} -> regex
      :error -> raise_invalid(pattern, param)
    end
  end

  defp text(pattern, _param) when is_binary(pattern), do: pattern
  defp text(pattern, _param) when is_atom(pattern), do: ModuleName.full(pattern)
  defp text(pattern, param), do: raise_invalid(pattern, param)

  defp raise_invalid(entry, param) do
    raise ArgumentError,
          "invalid #{param} entry #{inspect(entry)}: expected a module name pattern as a string, a plain module name, or either of those paired with a message"
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
