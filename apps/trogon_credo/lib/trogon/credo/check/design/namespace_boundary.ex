defmodule Trogon.Credo.Check.Design.NamespaceBoundary do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      forbidden: [],
      private_to: [],
      except: [],
      except_in: [],
      in_patterns: true,
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
           [forbidden: ["Acme.**"],
            except: ["Acme.**.Domain", "Acme.**.Domain.**"],
            files: %{included: ["lib/acme/*/domain/"]}]}

          # a domain error may only be built in the layers that own it
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: [{"Acme.**.Domain.**Error", "A domain error may only be raised from its own context."}],
            files: %{excluded: ["lib/acme/*/domain/", "lib/acme/*/command/"]}]}

      `forbidden` with `except` is a whitelist, as in the first example: forbid the
      whole application namespace, then except the part the domain layer may use.
      `forbidden` on its own says "must not depend on this one thing", scoped by
      `files:` to every file that is not itself part of the namespace being protected.

      A boundary that is the same rule in every namespace, an error module private to
      whichever service defines it, is written once with `private_to` rather than once
      per namespace. The parenthesized prefix of the pattern names the owning namespace,
      and what follows it is what that namespace keeps to itself.

          # an error is private to the service namespace that defines it
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [private_to: ["(Acme.*Service).**Error"]]}

          # a processor may not reach into another processor
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [private_to: ["(Acme.Processor.*)"],
            files: %{included: ["lib/acme/processor/"]}]}

      With the first configuration above, `Acme.BillingService.NotFoundError` may only
      be referenced from inside `Acme.BillingService`. A pattern that is only the
      parenthesized prefix, as in the second, makes a namespace private to itself, the
      module and everything under it. Ownership is read from the referencing file's own
      outermost module name, so `files:` narrows which files the rule applies to without
      changing who owns what. Where a pattern could bind the owning namespace in more
      than one place, the longest match wins, so the innermost namespace that satisfies
      the pattern is the owner.

      A boundary that has an exception on the referencing side, a namespace that is
      allowed to reach for what the rest may not, names that namespace in `except_in`.

          # only the adapter layer may reach for the HTTP client
          {Trogon.Credo.Check.Design.NamespaceBoundary,
           [forbidden: ["Acme.Http.**"],
            except_in: ["Acme.*.Adapter", "Acme.*.Adapter.**"]]}

      `except` names what may be referenced and `except_in` names who may reference it,
      so a rule with an exception that follows the module tree rather than the directory
      tree is written without a `files:` path. Ownership is read from the referencing
      file's own outermost module name, so a file with no `defmodule`, or whose
      outermost one is not written as an alias, is reported rather than excepted.

      `forbidden` and `private_to` express different rules, so one instance of the check
      sets one or the other.

      A pattern matches a fully qualified module name, anchored at both ends. Everything
      other than a wildcard is literal, including a character that would otherwise be
      regex syntax.

      | pattern | matches |
      | --- | --- |
      | `*` | any run of characters within a single segment, never crossing a `.` |
      | `**` | any run of characters including a `.`, so it crosses segments |
      | `Acme.Repo` | only that module |
      | `Acme.Repo.**` | `Acme.Repo.Account`, but not `Acme.Repo` itself |
      | `Acme.**.Domain.**` | `Acme.Billing.Domain.Invoice`, and `Acme.Domain.Invoice` too |
      | `Acme.**Error` | a module under `Acme` whose name ends in `Error`, at any depth |

      A `**` written as a whole segment is the one wildcard that can match nothing, so
      `Acme.**.Domain` names `Acme.Domain` as well as `Acme.Billing.Domain` and a
      pattern is not written twice to cover a level of nesting that is optional. A
      trailing `**` is the exception, reading as everything under the namespace, so a
      project that means the namespace root as well writes that as its own pattern.
      Anywhere else a wildcard matches at least one character, which is why
      `Acme.**Error`, glued to the literal it precedes, does not name `Acme.Error`.

      Reported: a qualified call, a struct literal or pattern, an `import`, `require`,
      or `use` target, each member of a multi form directive such as
      `Acme.Http.{Client, Server}`, and a module named as a plain value such as a
      capture or a tuple element, since each of those is how a file depends on a module. Aliases are
      resolved first, so a reference written through an alias is reported under what it
      resolves to, and a name the file binds to two modules resolves to neither.

      An Erlang module is reported too, under the name a pattern names it by, so a
      pattern `"os"` names the module `:os.system_time()` calls, and `"rand"` the one
      `alias :rand, as: Random` renames. A message names such a module as the atom it is
      written as, `:os`, since that is how the source spells it. The name has one
      segment, so a pattern for an Erlang module is written without a `.`, and a
      wildcard inside it, `"httpc*"`, matches within that one segment as it does
      anywhere else.

      Not reported: a `defmodule` head, at any depth, since a boundary is normally
      scoped to the namespace's own directory; a bare `alias`, in any of its forms,
      since an alias alone creates no dependency, the multi form included; the members
      of a multi form directive whose base is not written as an alias,
      `__MODULE__.{Foo}` for instance, since what the base stands for is only known at
      compile time; a module named in a typespec; anything inside a `quote` block, which
      belongs to wherever the macro expands; and an Erlang module named as a plain value
      rather than as a call or directive target, `spawn(:os, :timestamp, [])` for
      instance, since an atom on its own is indistinguishable from any other atom and
      reporting one would report `:ok` under a pattern such as `"o*"`. Under
      `private_to`, a reference in a file with no `defmodule`, or whose outermost
      `defmodule` name is not written as an alias, is not reported either, since the
      check cannot tell which namespace the reference is coming from.

      A reference written in a pattern matches on a value rather than building or
      calling one, so a project that means "this may be matched anywhere but only built
      where it belongs" sets `in_patterns` to `false`. A clause head, a function head, a
      `with` or `for` generator, the left of a match, and a `rescue` clause are then all
      skipped, while a `cond` condition and a `receive` timeout, expressions despite
      being written to the left of a `->`, are not. A struct built as a default argument value sits inside a
      function head, so it is skipped along with the rest of the head.

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
        private_to: """
        A pattern, or a list of patterns, whose parenthesized prefix names an owning
        namespace and whose remainder names what that namespace keeps private. A module
        matching the whole pattern may only be referenced from the namespace the prefix
        bound. A pattern that is only the parenthesized prefix makes the namespace
        private to itself, the module and everything under it. An entry may also be
        given as a `{pattern, "message"}` tuple carrying its own message. The default
        empty list makes the check inert, and setting this together with `forbidden`
        raises, since the two express different rules.
        """,
        except: """
        A list of module name patterns that carve exceptions out of `forbidden` or
        `private_to`. A reference matching any `except` pattern is never reported, even when
        it also matches a forbidden or private one. The pattern syntax is the one `forbidden`
        uses, without its
        `{pattern, "message"}` form, since an exception reports nothing and so has no message
        to carry. The default empty list means there is no exception; `nil` is also accepted
        and treated the same way.
        """,
        except_in: """
        A list of module name patterns matched against the referencing file's own
        outermost module name. A reference written in a module any of them names is never
        reported, which is how a boundary states its exception by namespace rather than by
        file path. The pattern syntax is the one `forbidden` uses. The default empty list
        means there is no exception; `nil` is also accepted and treated the same way.
        """,
        in_patterns: """
        Whether a reference written in a pattern is reported. A pattern matches on a value
        rather than building or calling one, so setting this to `false` reports only a
        reference in expression position, which is how a project says a module may be
        matched anywhere and only built where it belongs. Defaults to `true`, reporting a
        reference wherever it is written.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a project
        can say in its own words what to do instead. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]
  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  @erlang_module ~S<:(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[\p{L}\p{Nl}_][\p{L}\p{Nl}\p{Mn}\p{Mc}\p{Nd}\p{Pc}@]*[?!]?)>
  @before_dot ~r/#{@erlang_module}$/u
  @after_directive ~r/^(?:import|require|use)\s*\(?\s*(#{@erlang_module})/u

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    forbidden = Params.get(params, :forbidden, __MODULE__) || []
    private_to = Params.get(params, :private_to, __MODULE__) || []

    case rule(forbidden, private_to) do
      :unconfigured -> []
      :configured -> analyze(source_file, params, forbidden, private_to)
    end
  end

  defp rule([], []), do: :unconfigured

  defp rule(forbidden, private_to) when forbidden != [] and private_to != [] do
    raise ArgumentError,
          "invalid configuration: `forbidden` and `private_to` express different rules, so one instance of this check must set only one of them"
  end

  defp rule(_forbidden, _private_to), do: :configured

  defp analyze(source_file, params, forbidden, private_to) do
    except_in = prepare_except(Params.get(params, :except_in, __MODULE__) || [])
    own_module = owning_module(source_file, private_to, except_in)

    if excepted_in?(own_module, except_in) do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        forbidden: prepare_forbidden(forbidden),
        private_to: prepare_private_to(private_to),
        own_module: own_module,
        except: prepare_except(Params.get(params, :except, __MODULE__) || []),
        in_patterns: in_patterns(Params.get(params, :in_patterns, __MODULE__)),
        hint: Params.get(params, :hint, __MODULE__),
        aliases: ModuleName.collect_aliases(source_file)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context))
    end
  end

  defp owning_module(_source_file, [], []), do: nil
  defp owning_module(source_file, _private_to, _except_in), do: own_module(source_file)

  # A file whose own module the check cannot read cannot be told to be inside an
  # excepted namespace, and reporting it is the reading that keeps a rule from
  # being stepped around by a file that names itself in a way the check cannot
  # see.
  defp excepted_in?(nil, _except_in), do: false
  defp excepted_in?(own_module, except_in), do: Enum.any?(except_in, &Regex.match?(&1, own_module))

  defp in_patterns(in_patterns) when is_boolean(in_patterns), do: in_patterns

  defp in_patterns(in_patterns) do
    raise ArgumentError, "invalid in_patterns #{inspect(in_patterns)}: expected a boolean"
  end

  defp own_module(source_file) do
    source_file
    |> Credo.Code.prewalk(&outermost/2, {false, nil})
    |> elem(1)
  end

  defp outermost({:quote, _meta, _args}, acc), do: {[], acc}

  defp outermost({:defmodule, _meta, _args}, {true, name}), do: {[], {true, name}}

  defp outermost({:defmodule, _meta, [{:__aliases__, _alias_meta, parts} | _]}, {false, _name}) do
    {[], {true, readable_name(parts)}}
  end

  defp outermost({:defmodule, _meta, _args}, {false, _name}), do: {[], {true, nil}}

  defp outermost(ast, acc), do: {ast, acc}

  defp readable_name(parts) do
    if Enum.all?(parts, &is_atom/1) do
      ModuleName.full(parts)
    else
      nil
    end
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _context)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse({:alias, _meta, _args}, issues, _context), do: {[], issues}

  # A multi form directive names each of its members, so each one is read as a
  # reference and the form is left out of the walk, which keeps a member from
  # being read a second time as the bare name it is written with.
  defp traverse({{:., _meta, [{:__aliases__, _base_meta, base_parts}, :{}]}, _call_meta, members}, issues, context) do
    {[], Enum.reduce(members, issues, &report_member(&1, &2, base_parts, context))}
  end

  defp traverse({{:., _meta, [_base, :{}]}, _call_meta, _members}, issues, _context) do
    {[], issues}
  end

  defp traverse({:defmodule, meta, [_name | rest]}, issues, _context) do
    {{:defmodule, meta, [nil | rest]}, issues}
  end

  defp traverse({:cond, meta, [blocks]}, issues, %{in_patterns: false}) when is_list(blocks) do
    {{:cond, meta, [expose_clauses(blocks, :do)]}, issues}
  end

  defp traverse({:receive, meta, [blocks]}, issues, %{in_patterns: false}) when is_list(blocks) do
    {{:receive, meta, [expose_clauses(blocks, :after)]}, issues}
  end

  defp traverse({:->, _meta, [_pattern, body]}, issues, %{in_patterns: false}) do
    {body, issues}
  end

  defp traverse({operator, _meta, [_pattern, value]}, issues, %{in_patterns: false})
       when operator in [:=, :<-] do
    {value, issues}
  end

  defp traverse({kind, _meta, [{:when, _meta2, [_head, _guard]} | rest]}, issues, %{in_patterns: false})
       when kind in @definition_kinds do
    {rest, issues}
  end

  defp traverse({kind, _meta, [_head | rest]}, issues, %{in_patterns: false})
       when kind in @definition_kinds do
    {rest, issues}
  end

  # An Erlang module is written as a plain atom, which is only distinguishable
  # from any other atom where the source says the atom is a module: the target of
  # a qualified call, or of a directive.
  defp traverse({{:., dot_meta, [module, function]}, _call_meta, _args} = ast, issues, context)
       when is_atom(module) and is_atom(function) do
    {written, meta} = erlang_call(module, dot_meta, context)

    {ast, report_erlang(module, written, meta, issues, context)}
  end

  defp traverse({directive, meta, [module | _rest]} = ast, issues, context)
       when directive in [:import, :require, :use] and is_atom(module) and
              module not in [nil, true, false] do
    {written, meta} = erlang_directive(module, meta, context)

    {ast, report_erlang(module, written, meta, issues, context)}
  end

  defp traverse({:__aliases__, meta, parts} = ast, issues, context) do
    module = ModuleName.resolve(parts, context.aliases)

    {ast, maybe_report(module, meta, Name.full(parts), issues, context)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  # A member is reported under the name it is written with, rather than under the
  # whole form, so that the trigger reads as the source does at the column the
  # issue points at. The message still names the module the member resolves to.
  defp report_member({:__aliases__, meta, member_parts}, issues, base_parts, context) do
    module = ModuleName.resolve(base_parts ++ member_parts, context.aliases)

    maybe_report(module, meta, Name.full(member_parts), issues, context)
  end

  defp report_member(_member, issues, _base_parts, _context), do: issues

  defp report_erlang(module, written, meta, issues, context) do
    maybe_report(ModuleName.full(module), meta, written, issues, context)
  end

  # An Erlang module written as a plain atom carries no meta of its own, and the
  # source may spell it quoted, which `inspect/1` does not return. Both where it
  # is written and how it is spelled are read from the source text, which a call
  # writes immediately to the left of the dot.
  defp erlang_call(module, dot_meta, context) do
    with column when is_integer(column) <- dot_meta[:column],
         text when is_binary(text) <- line_text(dot_meta[:line], context),
         [written] <- Regex.run(@before_dot, String.slice(text, 0, column - 1)) do
      {written, Keyword.put(dot_meta, :column, column - String.length(written))}
    else
      _unread -> {inspect(module), Keyword.delete(dot_meta, :column)}
    end
  end

  # A directive names its target to the right of the directive itself, written
  # with or without parentheses.
  defp erlang_directive(module, meta, context) do
    with column when is_integer(column) <- meta[:column],
         text when is_binary(text) <- line_text(meta[:line], context),
         rest = String.slice(text, (column - 1)..-1//1),
         [{offset, length}] <-
           Regex.run(@after_directive, rest, return: :index, capture: :all_but_first) do
      {binary_part(rest, offset, length), Keyword.put(meta, :column, column + offset)}
    else
      _unread -> {inspect(module), Keyword.delete(meta, :column)}
    end
  end

  defp line_text(line, context) when is_integer(line) do
    context.issue_meta
    |> IssueMeta.source_file()
    |> SourceFile.line_at(line)
  end

  defp line_text(_line, _context), do: nil

  # A `cond` writes its conditions, and a `receive` its `after` timeout, on the
  # left of a `->`, where every other construct writes a pattern, so both sides
  # of those clauses are exposed as expressions.
  defp expose_clauses(blocks, key) do
    Enum.map(blocks, &expose_block(&1, key))
  end

  defp expose_block({key, clauses}, key) when is_list(clauses) do
    {key, Enum.map(clauses, &expose_clause/1)}
  end

  defp expose_block(block, _key), do: block

  defp expose_clause({:->, meta, args}), do: {:__block__, meta, args}
  defp expose_clause(clause), do: clause

  defp maybe_report(nil, _meta, _trigger, issues, _context), do: issues

  defp maybe_report(module, meta, trigger, issues, context) do
    case violation(module, context) do
      nil ->
        issues

      message ->
        [issue_for(context.issue_meta, meta, trigger, message, context.hint) | issues]
    end
  end

  defp violation(module, context) do
    if excepted?(module, context.except) do
      nil
    else
      forbidden_violation(module, context.forbidden) || private_violation(module, context)
    end
  end

  defp forbidden_violation(module, forbidden) do
    forbidden
    |> Enum.find(fn {regex, _message} -> Regex.match?(regex, module) end)
    |> forbidden_message(module)
  end

  defp private_violation(module, context) do
    Enum.find_value(context.private_to, &private_message(&1, module, context.own_module))
  end

  defp private_message({regex, message}, module, own_module) do
    case Regex.run(regex, module) do
      [_full, owner] -> owner_message(owner, module, message, own_module)
      nil -> nil
    end
  end

  defp owner_message(owner, module, message, own_module) do
    if inside_owner?(own_module, owner) do
      nil
    else
      message || "The module `#{ModulePattern.display(module)}` is private to `#{owner}`."
    end
  end

  defp inside_owner?(nil, _owner), do: true

  defp inside_owner?(own_module, owner) do
    own_module == owner or String.starts_with?(own_module, owner <> ".")
  end

  defp excepted?(module, except), do: Enum.any?(except, &Regex.match?(&1, module))

  defp forbidden_message(nil, _module), do: nil
  defp forbidden_message({_regex, nil}, module), do: default_message(module)
  defp forbidden_message({_regex, message}, _module), do: message

  defp default_message(module) do
    "A module in this namespace must not reference `#{ModulePattern.display(module)}`."
  end

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

  defp prepare_private_to(patterns) when is_list(patterns) do
    Enum.map(patterns, &prepare_private_entry/1)
  end

  defp prepare_private_to(pattern), do: [prepare_private_entry(pattern)]

  defp prepare_private_entry({pattern, message}) when is_binary(message) do
    {compile_private_pattern(pattern), message}
  end

  defp prepare_private_entry({_pattern, _message} = entry) do
    raise ArgumentError,
          "invalid private_to entry #{inspect(entry)}: the message in a {pattern, message} tuple must be a string"
  end

  defp prepare_private_entry(pattern) do
    {compile_private_pattern(pattern), nil}
  end

  defp compile_private_pattern(pattern) when is_binary(pattern) do
    case Regex.run(~r/^\(([^()]+)\)(.*)$/, pattern) do
      [_full, owner, ""] ->
        Regex.compile!("^(#{ModulePattern.source(owner)})(?:\\..+)?$")

      [_full, owner, "." <> _ = private] ->
        Regex.compile!("^(#{ModulePattern.source(owner)})#{ModulePattern.source(private)}$")

      _other ->
        raise ArgumentError, invalid_private_pattern(pattern)
    end
  end

  defp compile_private_pattern(pattern) do
    raise ArgumentError, invalid_private_pattern(pattern)
  end

  defp invalid_private_pattern(pattern) do
    "invalid private_to pattern #{inspect(pattern)}: expected a string of the form " <>
      "\"(owner)\" or \"(owner).private\", where the parenthesized prefix names the owning namespace"
  end

  defp prepare_except(patterns) do
    Enum.map(patterns, &compile_pattern/1)
  end

  defp compile_pattern(pattern) do
    case ModulePattern.compile(pattern) do
      {:ok, regex} ->
        regex

      :error ->
        raise ArgumentError,
              "invalid namespace boundary pattern #{inspect(pattern)}: expected a module name pattern as a string, or a plain module name"
    end
  end
end
