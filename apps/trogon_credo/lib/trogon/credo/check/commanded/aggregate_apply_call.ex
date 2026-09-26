defmodule Trogon.Credo.Check.Commanded.AggregateApplyCall do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    run_on_all: true,
    param_defaults: [
      aggregate_modules: [Trogon.Commanded.Aggregate],
      command_handler_modules: [Trogon.Commanded.CommandHandler],
      command_handler_case: Trogon.Commanded.TestSupport.CommandHandlerCase,
      hint: nil
    ],
    explanations: [
      check: """
      An aggregate's `apply/2` is a callback the framework calls to fold an event onto
      the current state. It is not meant to be called any other way: not from outside
      the module, where the only legitimate path to a new state is dispatching a
      command through the command handler, and not from inside the module either,
      where one clause calling another to reuse logic quietly turns `apply/2` into an
      ordinary function instead of the framework's single entry point.

      Calling it directly from outside builds a state the command handler could never
      produce, since none of the invariants the handler enforces ran on the way there.
      A test that does `MyAggregate.apply(aggregate, %SomethingHappened{})` is exercising
      a state nothing in production ever reaches. Calling it from inside, one clause
      to another, hides which clause actually produced a given state and makes the
      callback's dispatch harder to follow than a plain `case`. Both are calls to
      `apply/2` outside the framework's own dispatch, so this check reports both.

          {Trogon.Credo.Check.Commanded.AggregateApplyCall, []}

      Whether a module is an aggregate is not visible from a single file: the file
      that calls `apply/2` on it, a test in particular, rarely also brings in the
      `use` that marks the module an aggregate. This check runs on the whole analyzed
      set once, the same way `Trogon.Credo.Check.Design.ModuleCardinality` does, to
      first find every module whose body `use`s one of the `aggregate_modules`, and
      only then looks for calls to `apply` on any of them.

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

      What to do instead depends on where the call is, so the message does too. Inside
      the aggregate, the message suggests a private function the clauses share. Inside
      a command handler, a module whose body `use`s one of the
      `command_handler_modules`, the usual reason to call `apply/2` is to read the
      state an event would produce before emitting the next one, which is what
      `Commanded.Aggregate.Multi` already does: each `Multi.execute/2` step receives
      the aggregate with the events of the previous steps applied. Inside a test, a
      file whose name ends in `_test.exs`, the message suggests the
      `command_handler_case`, whose `assert_events/3`, `assert_state/3`, and
      `assert_error/3` reach a state by replaying events and dispatching a command
      through the handler. Anywhere else, the message suggests dispatching a command.

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
          hint: Params.get(params, :hint, __MODULE__)
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

  # Pass 2: calls to `apply` on a collected aggregate, from outside it or from within it.

  defp file_issues(source_file, settings, params) do
    ctx =
      Map.merge(settings, %{
        aliases: ModuleName.collect_aliases(source_file),
        test_file?: String.ends_with?(source_file.filename, "_test.exs"),
        issue_meta: IssueMeta.for(source_file, params)
      })

    source_file
    |> SourceFile.ast()
    |> visit([], {:other, nil}, ctx, [])
    |> Enum.reverse()
  end

  defp visit({:defmodule, _meta, [{:__aliases__, _ameta, parts}, body]}, prefix, _scope, ctx, issues)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      nested_prefix = prefix ++ parts
      visit(body, nested_prefix, module_scope(ModuleName.full(nested_prefix), body, ctx), ctx, issues)
    else
      issues
    end
  end

  defp visit({:defmodule, _meta, [_name, body]}, prefix, _scope, ctx, issues) do
    visit(body, prefix, {:other, nil}, ctx, issues)
  end

  defp visit({:quote, _meta, _args}, _prefix, _scope, _ctx, issues), do: issues

  # `def apply(...)`/`defp apply(...)` define the callback; the head is not a call.
  defp visit({def_kind, _meta, [head, kw]}, prefix, scope, ctx, issues)
       when def_kind in [:def, :defp] and is_list(kw) do
    if apply_head?(head) do
      visit(kw, prefix, scope, ctx, issues)
    else
      issues = visit(head, prefix, scope, ctx, issues)
      visit(kw, prefix, scope, ctx, issues)
    end
  end

  # A bodyless `def apply(...)` declaration; still not a call.
  defp visit({def_kind, _meta, [head]}, prefix, scope, ctx, issues)
       when def_kind in [:def, :defp] do
    if apply_head?(head), do: issues, else: visit(head, prefix, scope, ctx, issues)
  end

  # Local `apply(aggregate, event)`.
  defp visit({:apply, meta, args}, prefix, scope, ctx, issues) when is_list(args) and length(args) == 2 do
    issues = if aggregate?(scope), do: [inside_issue(ctx, "apply", meta) | issues], else: issues
    visit(args, prefix, scope, ctx, issues)
  end

  # Local `apply(mod, :apply, args)`.
  defp visit({:apply, meta, [mod_ref, second, args_list]}, prefix, scope, ctx, issues) do
    issues =
      if second == :apply do
        apply3_issue(mod_ref, scope, ctx, meta, "apply", issues)
      else
        issues
      end

    visit([mod_ref, args_list], prefix, scope, ctx, issues)
  end

  # Local `&apply/2` capture.
  defp visit({:&, _meta, [{:/, _meta2, [{:apply, hmeta, local_ctx}, 2]}]}, _prefix, scope, ctx, issues)
       when not is_list(local_ctx) do
    if aggregate?(scope), do: [inside_issue(ctx, "apply", hmeta) | issues], else: issues
  end

  # `aggregate |> apply(event)`.
  defp visit({:|>, _meta, [lhs, {:apply, meta2, args}]}, prefix, scope, ctx, issues)
       when is_list(args) and length(args) == 1 do
    issues = if aggregate?(scope), do: [inside_issue(ctx, "apply", meta2) | issues], else: issues
    issues = visit(lhs, prefix, scope, ctx, issues)
    visit(args, prefix, scope, ctx, issues)
  end

  # `__MODULE__.apply(...)`, also reached when this dot node is embedded in a pipe or a capture.
  defp visit({:., _meta, [{:__MODULE__, mmeta, _}, :apply]}, _prefix, scope, ctx, issues) do
    if aggregate?(scope), do: [inside_issue(ctx, "__MODULE__.apply", mmeta) | issues], else: issues
  end

  # `Mod.apply(...)`, also reached when embedded in a pipe or a capture.
  defp visit({:., _meta, [{:__aliases__, ameta, parts}, :apply]}, _prefix, scope, ctx, issues) do
    resolved = ModuleName.resolve(parts, ctx.aliases)

    if MapSet.member?(ctx.aggregates, resolved) do
      [aggregate_issue(ctx, scope, resolved, Name.full(parts), ameta) | issues]
    else
      issues
    end
  end

  # `Kernel.apply(mod, :apply, args)`, written with the literal `Kernel` name.
  defp visit(
         {{:., _dmeta, [{:__aliases__, kmeta, [:Kernel]}, :apply]}, _cmeta, [mod_ref, :apply, args_list]},
         prefix,
         scope,
         ctx,
         issues
       ) do
    issues = apply3_issue(mod_ref, scope, ctx, kmeta, "Kernel.apply", issues)
    issues = visit(mod_ref, prefix, scope, ctx, issues)
    visit(args_list, prefix, scope, ctx, issues)
  end

  defp visit({form, _meta, args}, prefix, scope, ctx, issues) when is_list(args) do
    issues = if is_tuple(form), do: visit(form, prefix, scope, ctx, issues), else: issues
    visit(args, prefix, scope, ctx, issues)
  end

  defp visit({left, right}, prefix, scope, ctx, issues) do
    visit(right, prefix, scope, ctx, visit(left, prefix, scope, ctx, issues))
  end

  defp visit(list, prefix, scope, ctx, issues) when is_list(list) do
    Enum.reduce(list, issues, &visit(&1, prefix, scope, ctx, &2))
  end

  defp visit(_ast, _prefix, _scope, _ctx, issues), do: issues

  defp apply_head?({:apply, _meta, args}) when is_list(args), do: true
  defp apply_head?({:when, _meta, [{:apply, _hmeta, args}, _guard]}) when is_list(args), do: true
  defp apply_head?(_head), do: false

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

  defp module_scope(module, body, ctx) do
    cond do
      MapSet.member?(ctx.aggregates, module) -> {:aggregate, module}
      own_use?(body, ctx.aliases, ctx.command_handlers) -> {:command_handler, module}
      true -> {:other, module}
    end
  end

  defp aggregate?({kind, _module}), do: kind == :aggregate

  defp aggregate_issue(ctx, {:aggregate, resolved}, resolved, trigger, meta) do
    inside_issue(ctx, trigger, meta)
  end

  defp aggregate_issue(ctx, {kind, _module}, resolved, trigger, meta) do
    format_issue(
      ctx.issue_meta,
      message: append_hint(outside_message(kind, resolved, ctx), ctx.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp inside_issue(ctx, trigger, meta) do
    format_issue(
      ctx.issue_meta,
      message: append_hint(inside_message(), ctx.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
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

  defp inside_message do
    "Extract the shared logic into a private function instead of calling `apply/2` from another `apply/2` " <>
      "clause, since `apply/2` is the aggregate's single entry point and is invoked only by the framework."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
