defmodule Trogon.Credo.Check.Commanded.AggregateStateConstruction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    run_on_all: true,
    param_defaults: [
      aggregate_modules: [Trogon.Commanded.Aggregate],
      command_handler_modules: [Trogon.Commanded.CommandHandler],
      command_handler_case: Trogon.Commanded.TestSupport.CommandHandlerCase,
      constructor_functions: [:new, :new!],
      hint: nil
    ],
    explanations: [
      check: """
      An aggregate's state is only ever meant to exist the way the framework builds
      it: a struct the command handler rehydrates by replaying events through
      `apply/2`. Nothing in production asks an aggregate for a fresh struct any other
      way, so this check forbids every other way a module can end up with one: a
      direct call to `apply/2`, a direct call to a constructor function such as
      `new/1` or `new!/1`, a struct literal or the struct update syntax naming the
      aggregate, and a direct call to `struct/2` or `struct!/2` naming it.

      `apply/2` is a callback the framework calls to fold an event onto the current
      state. It is not meant to be called any other way: not from outside the
      module, where the only legitimate path to a new state is dispatching a command
      through the command handler, and not from inside the module either, where one
      clause calling another to reuse logic quietly turns `apply/2` into an ordinary
      function instead of the framework's single entry point.

      Calling it directly from outside builds a state the command handler could
      never produce, since none of the invariants the handler enforces ran on the
      way there. A test that does `MyAggregate.apply(aggregate, %SomethingHappened{})`
      is exercising a state nothing in production ever reaches. Calling it from
      inside, one clause to another, hides which clause actually produced a given
      state and makes the callback's dispatch harder to follow than a plain `case`.
      Both are calls to `apply/2` outside the framework's own dispatch, so this check
      reports both.

      A constructor function, `new/1` and `new!/1` by default, builds an aggregate
      struct directly from attributes instead of from events, which production never
      does either: the only struct a command handler ever receives is one Commanded
      rehydrated by replaying events, never one a constructor assembled. A test that
      does `MyAggregate.new!(%{status: :approved})` is exercising a state nothing in
      production ever reaches, exactly like a direct `apply/2` call, so this check
      reports a constructor call the same way it reports an `apply/2` call: wherever
      it is written, with a message that points at where it was found. Calling a
      constructor from inside the aggregate itself is left alone, since the aggregate
      building its own struct, from `apply/2` or anywhere else in its own module, is
      exactly what the framework already allows it to do; what a constructor call
      from outside reaches is a state nothing but that call itself produces. Calling
      any other public function of the aggregate, a predicate or a helper that is not
      one of the `constructor_functions`, also stays allowed, even though exercising
      it from a test usually means constructing the aggregate first, which this check
      then catches at the construction site rather than at the predicate call.

      A struct literal, `%MyAggregate{status: :approved}`, builds a state the same
      way a constructor does, field by field, without a single event ever being
      replayed, so this check reports one the same way it reports a constructor
      call: wherever it names the aggregate with at least one field, outside the
      aggregate's own module. The struct update form, `%MyAggregate{aggregate |
      status: :approved}`, starts from an existing struct but still assigns a field
      the same direct way, so it is reported too. `struct/2` and `struct!/2`,
      written as `struct(MyAggregate, status: :approved)` or
      `Kernel.struct(MyAggregate, status: :approved)`, piped as `MyAggregate |>
      struct(status: :approved)`, or reached indirectly through `apply(Kernel,
      :struct, [MyAggregate, status: :approved])` or `Kernel.apply(Kernel, :struct,
      [MyAggregate, status: :approved])`, build the same state through a function
      instead of the `%{}` syntax and are reported the same way, as long as fields
      are actually given: `struct(MyAggregate)` and `struct(MyAggregate, [])` build
      nothing different from the empty struct below and are left alone, piped or not.
      `struct(%MyAggregate{}, status: :approved)` and `%MyAggregate{} |> struct(status:
      :approved)` name the same module the empty struct literal alone does, so they are
      reported the same way; a variable that happens to hold an aggregate struct at
      runtime is not, since nothing in the AST says what it holds.

      The empty struct literal, `%MyAggregate{}`, is never reported, however it is
      written and wherever it appears: `Commanded` rehydrates an aggregate by
      replaying events onto one, `Trogon.Commanded.ProtobufMapper` and the JSONB
      serializer both decode into one before filling in fields, and none of that is
      the construction this check exists to catch.

      A struct literal or update is only ever reported in expression position,
      somewhere its fields are actually evaluated to build a value: aliased, piped,
      assigned, passed as an argument, or nested inside another literal. A pattern
      never builds anything, so a struct shape is left alone wherever it only
      matches one: a function head, a `defmacro`, `defmacrop`, `defguard`, or
      `defguardp` head the same way, a `case` or `with` clause, the left side of a
      `=` (including a chain of them, `a = b = %MyAggregate{}`), `match?/2`'s first
      argument, and by extension `assert %MyAggregate{...} = some_expr`, which is
      itself a match. The same goes for ExUnit's own pattern positions: the first
      argument of `assert_receive`, `assert_received`, `refute_receive` and
      `refute_received`, and the context argument of `test "name", %{...} do ... end`
      and `setup`/`setup_all %{...} do ... end`. A macro's arguments are AST at expansion time, not the struct
      they might look like, so a struct shape in its head is a pattern the same way;
      one quoted in its body is a different matter, and like every `alias` and
      struct literal written inside a `quote` block, is not looked at. The right
      side of a `=` is not a pattern, so `x =
      %MyAggregate{status: :approved}` is still reported even though `=` is the same
      operator a pattern uses. A `cond` clause's condition is an expression, never a
      pattern, so it is checked the same way a plain expression is. Calling a struct
      literal, an update, or `struct/2` from inside the aggregate itself, in
      `apply/2` or anywhere else in its own module, stays allowed for the same
      reason a constructor call from inside it does: the aggregate building its own
      struct is exactly what the framework already lets it do.

          {Trogon.Credo.Check.Commanded.AggregateStateConstruction, []}

      Whether a module is an aggregate is not visible from a single file: the file
      that calls `apply/2` or a constructor on it, a test in particular, rarely also
      brings in the `use` that marks the module an aggregate. This check runs on the
      whole analyzed set once, the same way `Trogon.Credo.Check.Design.ModuleCardinality`
      does, to first find every module whose body `use`s one of the
      `aggregate_modules`, and only then looks for calls to `apply` or a constructor
      on any of them.

      Outside a collected aggregate, a call to `apply` on it is reported however it is
      written: `MyAggregate.apply(aggregate, event)`, piped, captured as
      `&MyAggregate.apply/2`, or reached indirectly through `apply(MyAggregate, :apply,
      args)` or `Kernel.apply(MyAggregate, :apply, args)`. A module resolves through
      the file's aliases first, so a call through an aliased name is still recognized,
      and a call written with an explicit `Elixir.` prefix names the same module and is
      reported the same way.

      Inside a collected aggregate, a call to its own `apply/2` is reported too, again
      however it is written: the bare `apply(aggregate, event)`, `__MODULE__.apply(...)`,
      piped as `aggregate |> apply(event)`, captured as `&apply/2` or
      `&__MODULE__.apply/2`, or reached through `apply(__MODULE__, :apply, args)` or
      `Kernel.apply(__MODULE__, :apply, args)`. The `def apply(...)` and `defp
      apply(...)` clauses that define the callback are not calls and are never
      reported, whatever they pattern match on or guard against; what a clause does
      with logic another clause also needs is share it through a private function
      instead. Neither an `apply/2` nor an `apply/3` call is reported in a module this
      check did not collect as an aggregate, local or not, since nothing marks it as
      the callback in the first place.

      A call to a constructor function is reported the same way a call to `apply` on
      another module is: written directly as `MyAggregate.new!(attrs)`, piped,
      captured as `&MyAggregate.new!/1`, or reached indirectly through
      `apply(MyAggregate, :new!, args)` or `Kernel.apply(MyAggregate, :new!, args)`,
      resolved through the file's aliases the same way `apply/2` calls are. A
      constructor call from inside the collected aggregate itself, written as
      `new(attrs)`, `__MODULE__.new(attrs)`, or with the module's own full name, is
      not reported, since the aggregate assembling its own struct is not the problem
      this check exists to catch.

      What to do instead depends on where the call is, so the message does too. For
      an `apply/2` call made inside the aggregate, the message suggests a private
      function the clauses share. For an `apply/2` call made inside a command
      handler, a module whose body `use`s one of the `command_handler_modules`, the
      usual reason to call `apply/2` is to read the state an event would produce
      before emitting the next one, which is what `Commanded.Aggregate.Multi` already
      does: each `Multi.execute/2` step receives the aggregate with the events of the
      previous steps applied. For a call to `apply/2` or a constructor made inside a
      test, a file whose name ends in `_test.exs`, the message suggests the
      `command_handler_case`, whose `assert_events/3` and `assert_error/3` reach a
      state by replaying events and dispatching a command through the handler;
      `assert_state/3` is never recommended, since recommending it would point a test
      that builds state directly right back at building state directly. Anywhere
      else, including a constructor call made inside a command handler, where
      `Commanded.Aggregate.Multi` has nothing to do with assembling an aggregate from
      attributes, the message suggests dispatching a command. A struct literal, a
      struct update, or a call to `struct/2` or `struct!/2` gets the same message a
      constructor call does, since it is exactly the same problem, including when
      it is found inside a command handler, where `Commanded.Aggregate.Multi` has
      nothing to do with a struct literal either.

      Aliases are collected for the whole file rather than per lexical scope, the same
      way `Trogon.Credo.Check.Warning.PreferredModule` collects them, except for an
      `alias` written inside a `quote` block, which takes effect wherever the macro
      expands and is therefore not collected. A name the file binds to more than one
      module matches neither module.
      """,
      params: [
        aggregate_modules: """
        A list of modules that mark a module as an aggregate when brought in with
        `use`. Defaults to `Trogon.Commanded.Aggregate` itself; a project that wraps it
        in a macro of its own, a `MyApp.Aggregate` that `use`s the base module and adds
        its own conventions, lists that wrapper here instead, since a module that
        `use`s the wrapper never writes `use Trogon.Commanded.Aggregate` directly.
        """,
        command_handler_modules: """
        A list of modules that mark a module as a command handler when brought in with
        `use`, so a call from one suggests `Commanded.Aggregate.Multi`. Defaults to
        `Trogon.Commanded.CommandHandler`.
        """,
        command_handler_case: """
        The test case module the message suggests for a call from a test. Defaults to
        `Trogon.Commanded.TestSupport.CommandHandlerCase`; a project that wraps it in a
        case template of its own names that wrapper here.
        """,
        constructor_functions: """
        A list of function names that build an aggregate struct directly from
        attributes instead of from events, reported the same way a direct `apply/2`
        call on another module is when called from outside the aggregate that defines
        them. Defaults to `[:new, :new!]`, the functions `use Trogon.Commanded.Aggregate`
        generates through `Trogon.Commanded.ValueObject`; a project that adds its own
        factory function to its aggregates lists it here too.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to `nil`,
        the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleName

  @doc false
  @impl true
  def run_on_all_source_files(exec, source_files, params) do
    markers = markers(params, :aggregate_modules)

    aggregates =
      source_files
      |> Enum.flat_map(&find_aggregates(&1, markers))
      |> MapSet.new()

    issues =
      if MapSet.size(aggregates) == 0 do
        []
      else
        settings = %{
          aggregates: aggregates,
          command_handlers: markers(params, :command_handler_modules),
          command_handler_case: ModuleName.full(Params.get(params, :command_handler_case, __MODULE__)),
          constructors: constructor_names(params),
          hint: Params.get(params, :hint, __MODULE__),
          # Not a public param: AggregateApplyCall sets this so its own issues still
          # carry its name, which is what a `credo:disable` comment naming it matches on.
          reporting_check: Keyword.get(params, :reporting_check, __MODULE__)
        }

        Enum.flat_map(source_files, &file_issues(&1, settings, params))
      end

    append_issues_and_timings(issues, exec)

    :ok
  end

  defp markers(params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> List.wrap()
    |> Enum.map(&ModuleName.full/1)
    |> MapSet.new()
  end

  defp constructor_names(params) do
    params
    |> Params.get(:constructor_functions, __MODULE__)
    |> List.wrap()
    |> MapSet.new()
  end

  # Pass 1: which modules, across the whole analyzed set, `use` one of the `aggregate_modules`.

  defp find_aggregates(source_file, markers) do
    aliases = ModuleName.collect_aliases(source_file)

    source_file
    |> SourceFile.ast()
    |> collect_aggregates([], aliases, markers, [])
    |> Enum.reverse()
  end

  defp collect_aggregates({:defmodule, _meta, [{:__aliases__, _ameta, parts}, body]}, prefix, aliases, markers, acc)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      nested_prefix = prefix ++ parts
      full_name = ModuleName.full(nested_prefix)

      acc = if own_use?(body, aliases, markers), do: [full_name | acc], else: acc

      collect_aggregates(body, nested_prefix, aliases, markers, acc)
    else
      acc
    end
  end

  defp collect_aggregates({:defmodule, _meta, [_name, _body]}, _prefix, _aliases, _markers, acc), do: acc
  defp collect_aggregates({:quote, _meta, _args}, _prefix, _aliases, _markers, acc), do: acc

  defp collect_aggregates({_form, _meta, args}, prefix, aliases, markers, acc) when is_list(args) do
    collect_aggregates(args, prefix, aliases, markers, acc)
  end

  defp collect_aggregates({left, right}, prefix, aliases, markers, acc) do
    collect_aggregates(right, prefix, aliases, markers, collect_aggregates(left, prefix, aliases, markers, acc))
  end

  defp collect_aggregates(list, prefix, aliases, markers, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_aggregates(&1, prefix, aliases, markers, &2))
  end

  defp collect_aggregates(_ast, _prefix, _aliases, _markers, acc), do: acc

  # A module's own `use`, not counting one that belongs to a nested `defmodule`.

  defp own_use?({:use, _meta, [{:__aliases__, _, parts} | _]}, aliases, markers) do
    MapSet.member?(markers, ModuleName.resolve(parts, aliases))
  end

  defp own_use?({:defmodule, _meta, _args}, _aliases, _markers), do: false
  defp own_use?({:quote, _meta, _args}, _aliases, _markers), do: false

  defp own_use?({_form, _meta, args}, aliases, markers) when is_list(args) do
    Enum.any?(args, &own_use?(&1, aliases, markers))
  end

  defp own_use?({left, right}, aliases, markers) do
    own_use?(left, aliases, markers) or own_use?(right, aliases, markers)
  end

  defp own_use?(list, aliases, markers) when is_list(list) do
    Enum.any?(list, &own_use?(&1, aliases, markers))
  end

  defp own_use?(_ast, _aliases, _markers), do: false

  # Pass 2: calls to `apply` or a constructor on a collected aggregate, from outside it or from within it.

  defp file_issues(source_file, settings, params) do
    ctx =
      Map.merge(settings, %{
        aliases: ModuleName.collect_aliases(source_file),
        test_file?: String.ends_with?(source_file.filename, "_test.exs"),
        issue_meta: IssueMeta.for(source_file, params)
      })

    source_file
    |> SourceFile.ast()
    |> visit([], {:other, nil}, false, ctx, [])
    |> Enum.reverse()
  end

  defp visit({:defmodule, _meta, [{:__aliases__, _ameta, parts}, body]}, prefix, _scope, pattern?, ctx, issues)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      nested_prefix = prefix ++ parts
      scope = module_scope(ModuleName.full(nested_prefix), body, ctx)
      visit(body, nested_prefix, scope, pattern?, ctx, issues)
    else
      visit(body, prefix, {:other, nil}, pattern?, ctx, issues)
    end
  end

  defp visit({:defmodule, _meta, [_name, body]}, prefix, _scope, pattern?, ctx, issues) do
    visit(body, prefix, {:other, nil}, pattern?, ctx, issues)
  end

  defp visit({:quote, _meta, _args}, _prefix, _scope, _pattern?, _ctx, issues), do: issues

  # `@spec`/`@callback`/`@macrocallback`/`@type`/`@typep`/`@opaque` are typespecs, not calls.
  defp visit({:@, _meta, [{attr_kind, _ameta, _attr_args}]}, _prefix, _scope, _pattern?, _ctx, issues)
       when attr_kind in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    issues
  end

  # `def apply(...)`/`defp apply(...)` define the callback; the head is not a call, and otherwise
  # is a pattern, except for each `\\` default in it, which the `\\` clause below splits back out.
  # `defmacro`/`defmacrop`/`defguard`/`defguardp` heads are patterns the same way, whatever they
  # match on: a macro's arguments are AST at expansion time, not the struct they might look like.
  defp visit({def_kind, _meta, [head, kw]}, prefix, scope, _pattern?, ctx, issues)
       when def_kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] and is_list(kw) do
    if apply_head?(head) do
      visit(kw, prefix, scope, false, ctx, issues)
    else
      issues = visit(head, prefix, scope, true, ctx, issues)
      visit(kw, prefix, scope, false, ctx, issues)
    end
  end

  # A bodyless `def apply(...)` declaration, or a `defguard`/`defguardp` (which never has a `do`
  # block); still not a call.
  defp visit({def_kind, _meta, [head]}, prefix, scope, _pattern?, ctx, issues)
       when def_kind in [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp] do
    if apply_head?(head), do: issues, else: visit(head, prefix, scope, true, ctx, issues)
  end

  # `defdelegate apply(...), to: X` declares the callback through another module; the head is not a call.
  defp visit({:defdelegate, _meta, [head, kw]}, prefix, scope, _pattern?, ctx, issues) when is_list(kw) do
    if apply_head?(head) do
      visit(kw, prefix, scope, false, ctx, issues)
    else
      issues = visit(head, prefix, scope, true, ctx, issues)
      visit(kw, prefix, scope, false, ctx, issues)
    end
  end

  # A `\\` default value in a function head is an expression even though the head around it sits
  # in a pattern position; the pattern it defaults for stays a pattern.
  defp visit({:\\, _meta, [default_pattern, default_value]}, prefix, scope, _pattern?, ctx, issues) do
    issues = visit(default_pattern, prefix, scope, true, ctx, issues)
    visit(default_value, prefix, scope, false, ctx, issues)
  end

  # `pattern = value`, already inside a pattern: destructuring, so both sides stay a pattern.
  defp visit({:=, _meta, [left, right]}, prefix, scope, true, ctx, issues) do
    issues = visit(left, prefix, scope, true, ctx, issues)
    visit(right, prefix, scope, true, ctx, issues)
  end

  # `pattern = value` at the expression level: the left side is a pattern, the right side is the
  # expression actually being evaluated.
  defp visit({:=, _meta, [left, right]}, prefix, scope, false, ctx, issues) do
    issues = visit(left, prefix, scope, true, ctx, issues)
    visit(right, prefix, scope, false, ctx, issues)
  end

  # `pattern <- enum`, a `with` qualifier or a `for` generator: the left side is a pattern, the
  # right side is an expression, regardless of where the generator sits.
  defp visit({:<-, _meta, [left, right]}, prefix, scope, _pattern?, ctx, issues) do
    issues = visit(left, prefix, scope, true, ctx, issues)
    visit(right, prefix, scope, false, ctx, issues)
  end

  # `cond`'s conditions are expressions, never patterns, even though they sit to the left of a
  # `->` the way a `case` clause's pattern does.
  defp visit({:cond, _meta, [[do: clauses]]}, prefix, scope, _pattern?, ctx, issues) when is_list(clauses) do
    Enum.reduce(clauses, issues, fn {:->, _cmeta, [conditions, body]}, acc ->
      acc = visit(conditions, prefix, scope, false, ctx, acc)
      visit(body, prefix, scope, false, ctx, acc)
    end)
  end

  # A `case`/`with`/`fn`/`receive` clause: the head is a pattern, the body is an expression.
  defp visit({:->, _meta, [head, body]}, prefix, scope, _pattern?, ctx, issues) do
    issues = visit(head, prefix, scope, true, ctx, issues)
    visit(body, prefix, scope, false, ctx, issues)
  end

  # `match?/2` compares a value against a pattern, so its first argument is a pattern position
  # even though the call itself is written as an expression, `Kernel.`-qualified or not.
  defp visit({:match?, _meta, [match_pattern, value]}, prefix, scope, _pattern?, ctx, issues) do
    issues = visit(match_pattern, prefix, scope, true, ctx, issues)
    visit(value, prefix, scope, false, ctx, issues)
  end

  defp visit(
         {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, :match?]}, _cmeta, [match_pattern, value]},
         prefix,
         scope,
         _pattern?,
         ctx,
         issues
       ) do
    issues = visit(match_pattern, prefix, scope, true, ctx, issues)
    visit(value, prefix, scope, false, ctx, issues)
  end

  # `assert_receive`/`assert_received`/`refute_receive`/`refute_received` match their first
  # argument against a message already in the mailbox, so it is a pattern; any other argument
  # (a timeout, a failure message) is an ordinary expression.
  defp visit({receive_assertion, _meta, [mailbox_pattern | rest]}, prefix, scope, _pattern?, ctx, issues)
       when receive_assertion in [:assert_receive, :assert_received, :refute_receive, :refute_received] and
              is_list(rest) do
    issues = visit(mailbox_pattern, prefix, scope, true, ctx, issues)
    visit(rest, prefix, scope, false, ctx, issues)
  end

  # `test "name", %{...} do ... end`: the context argument is a pattern destructuring the test
  # context, the same way a function head is; `do: ...` is sugar for the same keyword-list last
  # argument either way, so this covers both the block and the inline keyword form.
  defp visit({:test, _meta, [_name, context_pattern, do_block]}, prefix, scope, _pattern?, ctx, issues)
       when is_list(do_block) do
    issues = visit(context_pattern, prefix, scope, true, ctx, issues)
    visit(do_block, prefix, scope, false, ctx, issues)
  end

  # `setup %{...} do ... end`/`setup_all %{...} do ... end`: same context-pattern shape as
  # `test/3`, one argument earlier since there is no name. `setup do ... end` with no context
  # takes a single argument and has no pattern to treat specially, so it is left to the generic
  # call clause below.
  defp visit({setup_kind, _meta, [context_pattern, do_block]}, prefix, scope, _pattern?, ctx, issues)
       when setup_kind in [:setup, :setup_all] and is_list(do_block) do
    issues = visit(context_pattern, prefix, scope, true, ctx, issues)
    visit(do_block, prefix, scope, false, ctx, issues)
  end

  # Local `apply(aggregate, event)`.
  defp visit({:apply, meta, args}, prefix, scope, pattern?, ctx, issues) when is_list(args) and length(args) == 2 do
    issues = if aggregate?(scope), do: [inside_issue(ctx, "apply", meta) | issues], else: issues
    visit(args, prefix, scope, pattern?, ctx, issues)
  end

  # `apply(Kernel, :struct, [mod_ref, fields])`/`apply(Kernel, :struct!, [mod_ref, fields])`, the
  # indirect reflection form of `Kernel.struct/2`; unlike the clause below, the module being
  # built sits inside `args_list`, not in `apply/3`'s own first argument.
  defp visit(
         {:apply, meta, [{:__aliases__, _kmeta, [:Kernel]}, struct_fun, [mod_ref, fields]]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(mod_ref, fields, meta, scope, ctx, struct_fun, issues)
    visit([mod_ref, fields], prefix, scope, pattern?, ctx, issues)
  end

  # Local `apply(mod, fun_name, args)`, resolving to `apply` or a configured constructor.
  defp visit({:apply, meta, [mod_ref, fun_name, args_list]}, prefix, scope, pattern?, ctx, issues) do
    issues = target3_issue(mod_ref, fun_name, scope, ctx, meta, "apply", issues)
    visit([mod_ref, args_list], prefix, scope, pattern?, ctx, issues)
  end

  # Local `&apply/2` capture.
  defp visit({:&, _meta, [{:/, _meta2, [{:apply, hmeta, local_ctx}, 2]}]}, _prefix, scope, _pattern?, ctx, issues)
       when not is_list(local_ctx) do
    if aggregate?(scope), do: [inside_issue(ctx, "apply", hmeta) | issues], else: issues
  end

  # `aggregate |> apply(event)`.
  defp visit({:|>, _meta, [lhs, {:apply, meta2, args}]}, prefix, scope, pattern?, ctx, issues)
       when is_list(args) and length(args) == 1 do
    issues = if aggregate?(scope), do: [inside_issue(ctx, "apply", meta2) | issues], else: issues
    issues = visit(lhs, prefix, scope, pattern?, ctx, issues)
    visit(args, prefix, scope, pattern?, ctx, issues)
  end

  # `__MODULE__.apply(...)`, also reached when this dot node is embedded in a pipe or a capture.
  defp visit({:., _meta, [{:__MODULE__, mmeta, _}, :apply]}, _prefix, scope, _pattern?, ctx, issues) do
    if aggregate?(scope), do: [inside_issue(ctx, "__MODULE__.apply", mmeta) | issues], else: issues
  end

  # `Mod.apply(...)` or `Mod.new(...)`/`Mod.new!(...)` (or another configured constructor), also
  # reached when this dot node is embedded in a pipe or a capture.
  defp visit({:., _meta, [{:__aliases__, ameta, parts}, fun_name]}, _prefix, scope, _pattern?, ctx, issues)
       when is_atom(fun_name) do
    resolved = ModuleName.resolve(parts, ctx.aliases)

    cond do
      fun_name == :apply and MapSet.member?(ctx.aggregates, resolved) ->
        [aggregate_issue(ctx, scope, resolved, Name.full(parts), ameta) | issues]

      MapSet.member?(ctx.constructors, fun_name) and MapSet.member?(ctx.aggregates, resolved) and
          not self_call?(scope, resolved) ->
        [construction_issue(ctx, resolved, Name.full(parts), fun_name, ameta) | issues]

      true ->
        issues
    end
  end

  # `Kernel.apply(Kernel, :struct, [mod_ref, fields])`, the same reflection form as above, written
  # with the literal `Kernel` name on the outer `apply/3` call too.
  defp visit(
         {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, :apply]}, cmeta,
          [{:__aliases__, _kmeta2, [:Kernel]}, struct_fun, [mod_ref, fields]]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(mod_ref, fields, cmeta, scope, ctx, struct_fun, issues)
    visit([mod_ref, fields], prefix, scope, pattern?, ctx, issues)
  end

  # `Kernel.apply(mod, fun_name, args)`, written with the literal `Kernel` name.
  defp visit(
         {{:., _dmeta, [{:__aliases__, kmeta, [:Kernel]}, :apply]}, _cmeta, [mod_ref, fun_name, args_list]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when is_atom(fun_name) do
    issues = target3_issue(mod_ref, fun_name, scope, ctx, kmeta, "Kernel.apply", issues)
    issues = visit(mod_ref, prefix, scope, pattern?, ctx, issues)
    visit(args_list, prefix, scope, pattern?, ctx, issues)
  end

  # The struct update form, `%MyAggregate{aggregate | field: value}`. Elixir has no pattern form
  # for it, so it is reported regardless of the ambient context.
  defp visit(
         {:%, _meta, [name_ast, {:%{}, _mmeta, [{:|, _umeta, [source, fields]}]}]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       ) do
    issues = report_struct_update(name_ast, scope, ctx, issues)
    issues = visit(name_ast, prefix, scope, pattern?, ctx, issues)
    issues = visit(source, prefix, scope, false, ctx, issues)
    visit(fields, prefix, scope, false, ctx, issues)
  end

  # `%MyAggregate{}`, with no fields: Commanded, `Trogon.Commanded.ProtobufMapper`, and the JSONB
  # serializer all start deserializing from this, so it is never reported, pattern or expression.
  defp visit({:%, _meta, [_name_ast, {:%{}, _mmeta, []}]}, _prefix, _scope, _pattern?, _ctx, issues), do: issues

  # `%MyAggregate{field: value, ...}`, with at least one field: a pattern matches a value instead
  # of building one, so this is reported only as an expression.
  defp visit({:%, _meta, [name_ast, {:%{}, _mmeta, fields}]}, prefix, scope, pattern?, ctx, issues)
       when is_list(fields) do
    issues = if pattern?, do: issues, else: report_struct_literal(name_ast, scope, ctx, issues)
    issues = visit(name_ast, prefix, scope, pattern?, ctx, issues)
    visit(fields, prefix, scope, pattern?, ctx, issues)
  end

  # `struct(MyAggregate)`/`struct!(MyAggregate)`, with no fields: equivalent to the empty struct.
  defp visit({struct_fun, _meta, [mod_ref]}, prefix, scope, pattern?, ctx, issues)
       when struct_fun in [:struct, :struct!] do
    visit(mod_ref, prefix, scope, pattern?, ctx, issues)
  end

  # `struct(MyAggregate, fields)`/`struct!(MyAggregate, fields)`.
  defp visit({struct_fun, meta, [mod_ref, fields]}, prefix, scope, pattern?, ctx, issues)
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(mod_ref, fields, meta, scope, ctx, struct_fun, issues)
    issues = visit(mod_ref, prefix, scope, pattern?, ctx, issues)
    visit(fields, prefix, scope, pattern?, ctx, issues)
  end

  # `Kernel.struct(MyAggregate)`/`Kernel.struct!(MyAggregate)`, written with the literal `Kernel` name.
  defp visit(
         {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, struct_fun]}, _cmeta, [mod_ref]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    visit(mod_ref, prefix, scope, pattern?, ctx, issues)
  end

  # `Kernel.struct(MyAggregate, fields)`/`Kernel.struct!(MyAggregate, fields)`.
  defp visit(
         {{:., _dmeta, [{:__aliases__, kmeta, [:Kernel]}, struct_fun]}, _cmeta, [mod_ref, fields]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(mod_ref, fields, kmeta, scope, ctx, struct_fun, issues)
    issues = visit(mod_ref, prefix, scope, pattern?, ctx, issues)
    visit(fields, prefix, scope, pattern?, ctx, issues)
  end

  # `MyAggregate |> struct()`/`MyAggregate |> struct!()`, with no fields: equivalent to the empty
  # struct, the same way `struct(MyAggregate)` above is.
  defp visit({:|>, _meta, [lhs, {struct_fun, _meta2, []}]}, prefix, scope, pattern?, ctx, issues)
       when struct_fun in [:struct, :struct!] do
    visit(lhs, prefix, scope, pattern?, ctx, issues)
  end

  # `MyAggregate |> struct(fields)`/`MyAggregate |> struct!(fields)`, consistent with how
  # `aggregate |> apply(event)` above resolves a piped call.
  defp visit({:|>, _meta, [lhs, {struct_fun, meta2, [fields]}]}, prefix, scope, pattern?, ctx, issues)
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(lhs, fields, meta2, scope, ctx, struct_fun, issues)
    issues = visit(lhs, prefix, scope, pattern?, ctx, issues)
    visit(fields, prefix, scope, pattern?, ctx, issues)
  end

  # `MyAggregate |> Kernel.struct()`/`MyAggregate |> Kernel.struct!()`, with no fields.
  defp visit(
         {:|>, _meta, [lhs, {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, struct_fun]}, _cmeta, []}]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    visit(lhs, prefix, scope, pattern?, ctx, issues)
  end

  # `MyAggregate |> Kernel.struct(fields)`/`MyAggregate |> Kernel.struct!(fields)`, written with
  # the literal `Kernel` name.
  defp visit(
         {:|>, _meta, [lhs, {{:., _dmeta, [{:__aliases__, kmeta, [:Kernel]}, struct_fun]}, _cmeta, [fields]}]},
         prefix,
         scope,
         pattern?,
         ctx,
         issues
       )
       when struct_fun in [:struct, :struct!] do
    issues = report_struct_call(lhs, fields, kmeta, scope, ctx, struct_fun, issues)
    issues = visit(lhs, prefix, scope, pattern?, ctx, issues)
    visit(fields, prefix, scope, pattern?, ctx, issues)
  end

  defp visit({form, _meta, args}, prefix, scope, pattern?, ctx, issues) when is_list(args) do
    issues = if is_tuple(form), do: visit(form, prefix, scope, pattern?, ctx, issues), else: issues
    visit(args, prefix, scope, pattern?, ctx, issues)
  end

  defp visit({left, right}, prefix, scope, pattern?, ctx, issues) do
    visit(right, prefix, scope, pattern?, ctx, visit(left, prefix, scope, pattern?, ctx, issues))
  end

  defp visit(list, prefix, scope, pattern?, ctx, issues) when is_list(list) do
    Enum.reduce(list, issues, &visit(&1, prefix, scope, pattern?, ctx, &2))
  end

  defp visit(_ast, _prefix, _scope, _pattern?, _ctx, issues), do: issues

  defp apply_head?({:apply, _meta, args}) when is_list(args), do: true
  defp apply_head?({:when, _meta, [{:apply, _hmeta, args}, _guard]}) when is_list(args), do: true
  defp apply_head?(_head), do: false

  # Resolves `%MyAggregate{...}`'s or `struct(MyAggregate, ...)`'s module reference to the module
  # it names, the way `Mod.apply(...)` above resolves one, or to `nil` when it is not a plain
  # alias, for example `%__MODULE__{...}` or a variable holding the module at runtime; neither
  # names another aggregate from here, so there is nothing to resolve.
  defp resolved_target({:__aliases__, ameta, parts}, ctx),
    do: {ModuleName.resolve(parts, ctx.aliases), Name.full(parts), ameta}

  # `struct(%MyAggregate{}, fields)`/`%MyAggregate{} |> struct(fields)`: `struct/2` accepts an
  # existing struct in place of a module, and the empty struct literal names the same module
  # `%MyAggregate{}` alone would. A variable holding a struct at runtime is not resolved here
  # either, the same way a variable holding a module is not: neither names another aggregate from
  # the AST alone.
  defp resolved_target({:%, _meta, [name_ast, {:%{}, _mmeta, []}]}, ctx), do: resolved_target(name_ast, ctx)

  defp resolved_target(_mod_ref, _ctx), do: nil

  defp report_struct_literal(name_ast, scope, ctx, issues) do
    report_struct(name_ast, scope, ctx, issues, &struct_literal_issue/4)
  end

  defp report_struct_update(name_ast, scope, ctx, issues) do
    report_struct(name_ast, scope, ctx, issues, &struct_update_issue/4)
  end

  defp report_struct(name_ast, scope, ctx, issues, issue_fun) do
    case resolved_target(name_ast, ctx) do
      {resolved, trigger, ameta} ->
        if MapSet.member?(ctx.aggregates, resolved) and not self_call?(scope, resolved) do
          [issue_fun.(ctx, resolved, trigger, ameta) | issues]
        else
          issues
        end

      nil ->
        issues
    end
  end

  defp report_struct_call(mod_ref, fields, meta, scope, ctx, struct_fun, issues) do
    if empty_struct_fields?(fields) do
      issues
    else
      report_resolved_struct_call(resolved_target(mod_ref, ctx), meta, scope, ctx, struct_fun, issues)
    end
  end

  defp report_resolved_struct_call(nil, _meta, _scope, _ctx, _struct_fun, issues), do: issues

  defp report_resolved_struct_call({resolved, trigger, ameta}, meta, scope, ctx, struct_fun, issues) do
    if MapSet.member?(ctx.aggregates, resolved) and not self_call?(scope, resolved) do
      [struct_call_issue(ctx, resolved, trigger, struct_fun, ameta || meta) | issues]
    else
      issues
    end
  end

  defp empty_struct_fields?([]), do: true
  defp empty_struct_fields?({:%{}, _meta, []}), do: true
  defp empty_struct_fields?(_fields), do: false

  # Resolves an indirect `apply(mod_ref, fun_name, args)` call (local or through `Kernel.apply/3`)
  # to either the `apply/2` callback rules or the constructor rules, depending on `fun_name`.
  defp target3_issue(mod_ref, :apply, scope, ctx, meta, trigger, issues) do
    apply3_issue(mod_ref, scope, ctx, meta, trigger, issues)
  end

  defp target3_issue(mod_ref, fun_name, scope, ctx, _meta, _trigger, issues) do
    if MapSet.member?(ctx.constructors, fun_name) do
      constructor3_issue(mod_ref, fun_name, scope, ctx, issues)
    else
      issues
    end
  end

  defp apply3_issue({:__MODULE__, _, _}, scope, ctx, meta, trigger, issues) do
    if aggregate?(scope), do: [inside_issue(ctx, trigger, meta) | issues], else: issues
  end

  defp apply3_issue({:__aliases__, ameta, parts}, scope, ctx, _meta, _trigger, issues) do
    resolved = ModuleName.resolve(parts, ctx.aliases)

    if MapSet.member?(ctx.aggregates, resolved) do
      [aggregate_issue(ctx, scope, resolved, Name.full(parts), ameta) | issues]
    else
      issues
    end
  end

  defp apply3_issue(_mod_ref, _scope, _ctx, _meta, _trigger, issues), do: issues

  defp constructor3_issue({:__MODULE__, _, _}, _fun_name, _scope, _ctx, issues), do: issues

  defp constructor3_issue({:__aliases__, ameta, parts}, fun_name, scope, ctx, issues) do
    resolved = ModuleName.resolve(parts, ctx.aliases)

    if MapSet.member?(ctx.aggregates, resolved) and not self_call?(scope, resolved) do
      [construction_issue(ctx, resolved, Name.full(parts), fun_name, ameta) | issues]
    else
      issues
    end
  end

  defp constructor3_issue(_mod_ref, _fun_name, _scope, _ctx, issues), do: issues

  defp module_scope(module, body, ctx) do
    cond do
      MapSet.member?(ctx.aggregates, module) -> {:aggregate, module}
      own_use?(body, ctx.aliases, ctx.command_handlers) -> {:command_handler, module}
      true -> {:other, module}
    end
  end

  defp aggregate?({kind, _module}), do: kind == :aggregate

  defp self_call?({:aggregate, resolved}, resolved), do: true
  defp self_call?(_scope, _resolved), do: false

  defp aggregate_issue(ctx, {:aggregate, resolved}, resolved, trigger, meta) do
    inside_issue(ctx, trigger, meta)
  end

  defp aggregate_issue(ctx, {kind, _module}, resolved, trigger, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(outside_message(kind, resolved, ctx), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp construction_issue(ctx, resolved, trigger, fun_name, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(construction_message("#{resolved}.#{fun_name}", ctx), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp struct_literal_issue(ctx, resolved, trigger, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(construction_message("%#{resolved}{...}", ctx), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp struct_update_issue(ctx, resolved, trigger, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(construction_message("%#{resolved}{... | ...}", ctx), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp struct_call_issue(ctx, resolved, trigger, struct_fun, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(construction_message("#{struct_fun}(#{resolved}, ...)", ctx), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp inside_issue(ctx, trigger, meta) do
    Check.format_issue(
      ctx.issue_meta,
      [
        message: append_hint(inside_message(), ctx.hint),
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      ],
      ctx.reporting_check
    )
  end

  defp outside_message(:command_handler, resolved, _ctx) do
    "Use `Commanded.Aggregate.Multi` instead of calling `#{resolved}.apply/2` directly, " <>
      "since `Multi.execute/2` hands each step the aggregate with the previous step's events already applied."
  end

  defp outside_message(_kind, resolved, %{test_file?: true} = ctx) do
    "Test through the command handler with `#{ctx.command_handler_case}` instead of calling " <>
      "`#{resolved}.apply/2` directly, since that builds a state the command handler could never produce."
  end

  defp outside_message(_kind, resolved, _ctx) do
    "Dispatch a command through the command handler instead of calling `#{resolved}.apply/2` directly, " <>
      "since that bypasses the command handler and can build a state the handler could never produce."
  end

  defp construction_message(trigger_text, %{test_file?: true} = ctx) do
    "Test through the command handler with `#{ctx.command_handler_case}` instead of calling " <>
      "`#{trigger_text}` directly, since that builds a state nothing in production ever reaches; use " <>
      "`assert_events/3` or `assert_error/3` with the events that lead to the state you want to exercise."
  end

  defp construction_message(trigger_text, _ctx) do
    "Dispatch a command through the command handler instead of calling `#{trigger_text}` directly, " <>
      "since that builds a state nothing in production ever reaches."
  end

  defp inside_message do
    "Extract the shared logic into a private function instead of calling `apply/2` from another `apply/2` " <>
      "clause, since `apply/2` is the aggregate's single entry point and is invoked only by the framework."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
