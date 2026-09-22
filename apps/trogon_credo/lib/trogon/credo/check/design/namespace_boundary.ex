defmodule Trogon.Credo.Check.Design.NamespaceBoundary do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      forbidden: [],
      except: [],
      hint: nil
    ],
    explanations: [
      check: """
      An architectural boundary is usually written in a document and enforced by
      review: a domain layer that must not reach for the repository, an error module
      that only its own namespace may construct. This check expresses that boundary as
      configuration, enforced in the lint pass that already reads every file rather
      than in an architecture test that needs a compiled build.

      A project scopes an instance to the side of the boundary it constrains with
      Credo's own `files:` param, and lists what that side may not reach for in
      `forbidden`. Enabling the check again with different params expresses a second
      boundary.

          # a domain layer may only reach for itself and the shared domain namespace
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: ["MyApp.**"],
            except: ["MyApp.**.Domain.**", "MyApp.Domain", "MyApp.Domain.**"],
            files: %{included: ["lib/my_app/*/domain/"]}]}

          # an error module is private to the namespace that defines it
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: [{"MyApp.**.Domain.**Error", "A domain error may only be raised from its own context."}],
            files: %{excluded: ["lib/my_app/*/domain/", "lib/my_app/*/command/"]}]}

      `forbidden` with `except` is a whitelist, as in the first example: forbid the
      whole application namespace, then except the part the domain layer may use.
      `forbidden` on its own says "must not depend on this one thing", scoped by
      `files:` to every file that is not itself part of the namespace being protected.

      A pattern matches a fully qualified module name, anchored at both ends. Everything
      other than a wildcard is literal, including a character that would otherwise be
      regex syntax.

      | pattern | matches |
      | --- | --- |
      | `*` | any run of characters within a single segment, never crossing a `.` |
      | `**` | any run of characters including a `.`, so it crosses segments |
      | `MyApp.Repo` | only that module |
      | `MyApp.Repo.**` | `MyApp.Repo.Account`, but not `MyApp.Repo` itself |
      | `MyApp.**.Domain.**` | `MyApp.Billing.Domain.Invoice`, but not `MyApp.Domain.Invoice` |
      | `MyApp.**Error` | any module under `MyApp` whose name ends in `Error`, at any depth |

      A project that means both a namespace and its root writes both patterns, since
      `**` must still match at least one character.

      Reported: a qualified call, a struct literal or pattern, an `import`, `require`,
      or `use` target, and a module named as a plain value such as a capture or a tuple
      element, since each of those is how a file depends on a module. Aliases are
      resolved first, so a reference written through an alias is reported under what it
      resolves to, and a name the file binds to two modules resolves to neither.

      Not reported: a `defmodule` head, at any depth, since a boundary is normally
      scoped to the namespace's own directory; a bare `alias`, in any of its forms,
      since an alias alone creates no dependency; the members of a multi form directive
      such as `MyApp.{Foo, Bar}`, which a project writes out separately if it needs them
      checked; a module named in a typespec; anything inside a `quote` block, which
      belongs to wherever the macro expands; and an Erlang module written as a plain
      atom, `:os.system_time()` for instance, which no pattern has an atom form to
      match and which `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` covers.

      This check reads what a file writes, so it catches the realistic mistake and
      misses what it cannot see: a reference reached transitively, built with `apply/3`,
      read out of config, or injected by a macro. A boundary needing the transitive
      closure wants an architecture test over a compiled build; this is the fast, per
      file part of the same rule.

      It narrows Credo's `Credo.Check.Warning.ForbiddenModule` by matching namespace
      patterns rather than one module at a time, by carving exceptions with `except`,
      and by resolving aliases before matching.
      """,
      params: [
        forbidden: """
        A list of module name patterns, given as strings, or as `{pattern, "message"}`
        tuples that each carry their own message. A plain module name, given as an atom, is
        also accepted and matches only that exact module. The default empty list makes the
        check inert, since there is no universal boundary; a project configures its own with
        `forbidden` and, usually, with `files:`.
        """,
        except: """
        A list of module name patterns that carve exceptions out of `forbidden`. A reference
        matching any `except` pattern is never reported, even when it also matches a
        `forbidden` one. The pattern syntax is the one `forbidden` uses, without its
        `{pattern, "message"}` form, since an exception reports nothing and so has no message
        to carry. The default empty list means there is no exception; `nil` is also accepted
        and treated the same way.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a project
        can say in its own words what to do instead. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    case Params.get(params, :forbidden, __MODULE__) do
      forbidden when forbidden in [nil, []] ->
        []

      forbidden ->
        context = %{
          issue_meta: IssueMeta.for(source_file, params),
          forbidden: prepare_forbidden(forbidden),
          except: prepare_except(Params.get(params, :except, __MODULE__) || []),
          hint: Params.get(params, :hint, __MODULE__),
          aliases: ModuleName.collect_aliases(source_file)
        }

        Credo.Code.prewalk(source_file, &traverse(&1, &2, context))
    end
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _context)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse({:alias, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse({{:., _meta, [_base, :{}]}, _call_meta, _members}, issues, _context) do
    {[], issues}
  end

  defp traverse({:defmodule, meta, [_name | rest]}, issues, _context) do
    {{:defmodule, meta, [nil | rest]}, issues}
  end

  defp traverse({:__aliases__, meta, parts} = ast, issues, context) do
    module = ModuleName.resolve(parts, context.aliases)

    {ast, maybe_report(module, meta, Name.full(parts), issues, context)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp maybe_report(nil, _meta, _trigger, issues, _context), do: issues

  defp maybe_report(module, meta, trigger, issues, context) do
    case match_forbidden(module, context.forbidden, context.except) do
      nil ->
        issues

      message ->
        [issue_for(context.issue_meta, meta, trigger, message, context.hint) | issues]
    end
  end

  defp match_forbidden(module, forbidden, except) do
    if excepted?(module, except) do
      nil
    else
      forbidden
      |> Enum.find(fn {regex, _message} -> Regex.match?(regex, module) end)
      |> forbidden_message(module)
    end
  end

  defp excepted?(module, except), do: Enum.any?(except, &Regex.match?(&1, module))

  defp forbidden_message(nil, _module), do: nil
  defp forbidden_message({_regex, nil}, module), do: default_message(module)
  defp forbidden_message({_regex, message}, _module), do: message

  defp default_message(module), do: "A module in this namespace must not reference `#{module}`."

  defp issue_for(issue_meta, meta, trigger, message, hint) do
    format_issue(
      issue_meta,
      message: append_hint(message, hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"

  defp prepare_forbidden(patterns) do
    Enum.map(patterns, &prepare_forbidden_entry/1)
  end

  defp prepare_forbidden_entry({pattern, message}) when is_binary(message) do
    {compile_pattern(pattern), message}
  end

  defp prepare_forbidden_entry({_pattern, _message} = entry) do
    raise ArgumentError,
          "invalid forbidden entry #{inspect(entry)}: the message in a {pattern, message} tuple must be a string"
  end

  defp prepare_forbidden_entry(pattern) do
    {compile_pattern(pattern), nil}
  end

  defp prepare_except(patterns) do
    Enum.map(patterns, &compile_pattern/1)
  end

  defp compile_pattern(pattern) when is_binary(pattern) do
    to_regex(pattern)
  end

  defp compile_pattern(pattern) when is_atom(pattern) do
    pattern |> ModuleName.full() |> to_regex()
  end

  defp compile_pattern(pattern) do
    raise ArgumentError,
          "invalid namespace boundary pattern #{inspect(pattern)}: expected a module name pattern as a string, or a plain module name"
  end

  defp to_regex(pattern) do
    regex_source =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".+")
      |> String.replace("\\*", "[^.]+")

    Regex.compile!("^#{regex_source}$")
  end
end
