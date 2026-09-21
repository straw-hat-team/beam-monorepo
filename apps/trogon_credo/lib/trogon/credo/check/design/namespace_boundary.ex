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
      An architectural boundary is usually written down in a document and enforced by
      review: a domain layer that must not reach for the repository, a set of background
      workers that must not call each other, an error module that only its own namespace
      may construct. This check expresses that boundary as configuration and enforces it
      over source, in the same lint pass that already reads every other file, rather than
      as a separate architecture test that needs a compiled build, runs in the slow part of
      CI, and cannot see test files at all.

      A project scopes an instance of this check to the side of the boundary it is
      constraining, using Credo's own `files:` param, and lists the namespaces that side may
      not reach for in `forbidden`. The same check module can be enabled several times with
      different params, which is how one project expresses several boundaries.

          # a domain layer may only reach for itself and the shared domain namespace
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: ["MyApp.**"],
            except: ["MyApp.**.Domain.**", "MyApp.Domain", "MyApp.Domain.**"],
            files: %{included: ["lib/my_app/*/domain/"]}]}

          # an error module is private to the namespace that defines it
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: [{"MyApp.**.Domain.**Error", "A domain error may only be raised from its own context."}],
            files: %{excluded: ["lib/my_app/*/domain/", "lib/my_app/*/command/"]}]}

      `forbidden` plus `except` is how a whitelist is expressed: the first example forbids
      the whole application namespace and then excepts the part a domain layer may use,
      which reads as "must not depend on anything outside the domain namespace" without
      listing every module the domain namespace is allowed to see. The second example uses
      `forbidden` on its own to express the opposite direction, "must not depend on this one
      thing", scoped by `files: excluded:` to every file that is not itself part of the
      namespace the rule protects.

      A pattern matches a fully qualified module name as a string, anchored at both ends.
      `*` matches any run of characters within a single segment, so it never crosses a `.`.
      `**` matches any run of characters, including a `.`, so it crosses segments. Everything
      else in a pattern is literal, including a character that would otherwise be regex
      syntax. `"MyApp.Repo"` matches only that module. `"MyApp.Repo.**"` matches
      `MyApp.Repo.Account` but not `MyApp.Repo` itself, since `**` must still match at least
      one character, so a project that means both writes both patterns. `"MyApp.**.Domain.**"`
      matches `MyApp.Billing.Domain.Invoice` and requires at least one segment on each side of
      `Domain`, so it does not match `MyApp.Domain.Invoice`. `"MyApp.**Error"` matches any
      module under `MyApp` whose name ends in `Error`, at any depth.

      Aliases are resolved before matching, so a reference written through an alias is
      reported under the module it resolves to. A name the file binds to more than one
      module, two sibling modules aliasing a different `Client` for instance, resolves to
      neither, since the file as a whole does not say which one a given reference means.

      This check reports a qualified call, a struct literal or a struct pattern in a function
      head, an `import`, `require`, or `use` target, and a module named as a plain value,
      such as a function capture or a tuple element, since all of these are how a file
      depends on a module. It reports the same way regardless of which of these forms a
      reference takes, and regardless of where in the file it appears, because a boundary a
      project writes down is about the dependency, not the syntax that creates it.

      It does NOT report the name in a `defmodule` head, at any nesting depth, since a
      boundary that forbids a namespace is normally scoped to that namespace's own directory,
      and a module's own name would otherwise be the first thing reported. It does NOT report
      a bare `alias`, in any of its forms, including a renamed or a multi alias, since an
      alias on its own creates no dependency; if the aliased module is then used, that use is
      itself a reference and is reported there, so an unused alias to a forbidden module is
      silently allowed. It does NOT resolve a multi form `import`, `require`, or `use`, such
      as `MyApp.{Foo, Bar}`, into its individual members, since doing so correctly would
      require tracking the base separately from each member; a project that needs that form
      checked can write each dependency as a separate directive. It does NOT report a module
      named inside a typespec (`@spec`, `@type`, `@typep`, `@opaque`, `@callback`, or
      `@macrocallback`), since naming a module in a spec is not depending on it at runtime.
      Code inside a `quote` block is not analyzed either, since a reference written there
      belongs to wherever the macro expands rather than to the file that defines the macro.
      It also does NOT report a reference to an Erlang module written as a plain atom, such as
      `:os.system_time()`, since a boundary here is expressed over an application's own
      namespace and a pattern has no atom form to match against. A project that needs to
      forbid a specific Erlang call wants
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` instead, which matches an
      Erlang module given as an atom.

      This check sees the references a file writes, so it catches the realistic mistake,
      which is a developer writing the forbidden alias or call directly in the file. It does
      not see a reference reached transitively through a module that is itself allowed, one
      built at runtime with `apply/3`, one read back out of a module attribute or application
      config, or one injected by a macro that expands elsewhere. A project that needs the
      transitive closure of a boundary, rather than the direct references a single file
      writes, wants a whole project architecture test that runs against a compiled build;
      this check is the fast, per file part of the same rule.

      Credo ships `Credo.Check.Warning.ForbiddenModule` to forbid a fixed list of modules
      outright. This check differs in every way that a boundary needs and that check does
      not offer: a pattern here can match a whole namespace instead of one module at a time,
      `except` can carve a whitelist out of a forbidden namespace, a reference written
      through an alias is resolved before matching instead of compared as written, and a
      module's own `defmodule` head is excluded so the check does not flag a module for
      merely existing where its own name happens to match the pattern that protects it.
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
        A list of patterns, in the same syntax as `forbidden`, that carve exceptions out of
        it. A reference matching any `except` pattern is never reported, even when it also
        matches a `forbidden` one. The default empty list means there is no exception; `nil`
        is also accepted and treated the same way.
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
