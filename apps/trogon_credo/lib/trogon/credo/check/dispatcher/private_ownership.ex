defmodule Trogon.Credo.Check.Dispatcher.PrivateOwnership do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      middleware_modules: [Trogon.Dispatcher.Middleware],
      context_modules: [Trogon.Dispatcher.Context],
      except_in: ["Trogon.Dispatcher", "Trogon.Dispatcher.**"],
      hint: nil
    ],
    explanations: [
      check: """
      `Trogon.Dispatcher.Context.put_private/3`'s private slot is namespaced by the module
      writing to it, exactly so two middlewares never collide: each one reads back only what
      it wrote, with `get_private/3` passed the same owner. Naming another module as the
      owner breaks that namespacing on purpose, writing into a slot some other middleware
      reads from, or a slot nothing reads from because nothing names it again.

      This check reports `Context.put_private(context, owner, value)`, inside a module that
      implements `Trogon.Dispatcher.Middleware`, when `owner` is written as a literal module
      name that is not `__MODULE__` and does not resolve to the enclosing module itself.

          # preferred
          def call(context, next, _options) do
            context |> Context.put_private(__MODULE__, tenant) |> next.()
          end

          # NOT preferred
          def call(context, next, _options) do
            context |> Context.put_private(OtherMiddleware, tenant) |> next.()
          end

      Reported: a call to `put_private/3` on one of `context_modules`, written piped or not,
      whose owner argument is a literal module alias naming anything other than the module the
      call is written in.

      Not reported: `get_private/3`, since reading from another module's slot does not break
      its namespacing the way writing to it does; `put_private/3` whose owner is `__MODULE__`,
      or a literal alias that resolves to the enclosing module by its own name; a dynamic
      owner, a variable or any other expression, since there is nothing to resolve statically;
      any call outside a module that implements one of `middleware_modules`; and anything under
      `except_in`.
      """,
      params: [
        middleware_modules: """
        A list of modules that mark a module as a middleware when brought in with
        `@behaviour`. Defaults to `Trogon.Dispatcher.Middleware`.
        """,
        context_modules: """
        A list of modules whose `put_private/3` is checked. Defaults to
        `Trogon.Dispatcher.Context`.
        """,
        except_in: """
        A list of module name patterns, in the grammar
        `Trogon.Credo.Check.Design.NamespaceBoundary` documents for `private_to`, read against
        a file's own outermost module. A file whose module matches one of these is never
        scanned. Defaults to `Trogon.Dispatcher` and everything under it, the dispatcher's own
        namespace.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a project can
        say in its own words what to do instead. Skipped when set to `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    except_in = params |> Params.get(:except_in, __MODULE__) |> List.wrap() |> Enum.map(&ModulePattern.compile!/1)
    own_module = ModuleDeclaration.outermost_module_name(source_file)

    if excepted?(own_module, except_in) do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        aliases: ModuleName.collect_aliases(source_file),
        middleware_modules: markers(params, :middleware_modules),
        context_modules: markers(params, :context_modules),
        hint: Params.get(params, :hint, __MODULE__)
      }

      source_file
      |> SourceFile.ast()
      |> visit([], {:other, nil}, context, [])
      |> Enum.reverse()
    end
  end

  defp excepted?(nil, _except_in), do: false
  defp excepted?(own_module, except_in), do: Enum.any?(except_in, &Regex.match?(&1, own_module))

  defp markers(params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> List.wrap()
    |> Enum.map(&ModuleName.full/1)
    |> MapSet.new()
  end

  # Whether a module's own body, not counting a nested `defmodule`, declares
  # `@behaviour` naming one of the markers.

  defp own_behaviour?({:@, _meta, [{:behaviour, _bmeta, [{:__aliases__, _ameta, parts}]}]}, aliases, markers) do
    MapSet.member?(markers, ModuleName.resolve(parts, aliases))
  end

  defp own_behaviour?({:defmodule, _meta, _args}, _aliases, _markers), do: false
  defp own_behaviour?({:quote, _meta, _args}, _aliases, _markers), do: false

  defp own_behaviour?({_form, _meta, args}, aliases, markers) when is_list(args) do
    Enum.any?(args, &own_behaviour?(&1, aliases, markers))
  end

  defp own_behaviour?({left, right}, aliases, markers) do
    own_behaviour?(left, aliases, markers) or own_behaviour?(right, aliases, markers)
  end

  defp own_behaviour?(list, aliases, markers) when is_list(list) do
    Enum.any?(list, &own_behaviour?(&1, aliases, markers))
  end

  defp own_behaviour?(_ast, _aliases, _markers), do: false

  # The traversal, scoped per `defmodule` the file declares.

  defp visit({:defmodule, _meta, [{:__aliases__, _ameta, parts}, body]}, prefix, _scope, ctx, issues)
       when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      nested_prefix = prefix ++ parts
      visit(body, nested_prefix, module_scope(nested_prefix, body, ctx), ctx, issues)
    else
      visit(body, prefix, {:other, nil}, ctx, issues)
    end
  end

  defp visit({:defmodule, _meta, [_name, body]}, prefix, _scope, ctx, issues) do
    visit(body, prefix, {:other, nil}, ctx, issues)
  end

  defp visit({:quote, _meta, _args}, _prefix, _scope, _ctx, issues), do: issues

  defp visit({:@, _meta, [{attr_kind, _ameta, _attr_args}]}, _prefix, _scope, _ctx, issues)
       when attr_kind in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    issues
  end

  # `Context.put_private(context, owner, value)`, not piped.
  defp visit(
         {{:., _dmeta, [{:__aliases__, _ameta, parts}, :put_private]}, cmeta, [_ctx_arg, owner_ast, _value_ast]} =
           ast,
         prefix,
         scope,
         ctx,
         issues
       ) do
    issues = report_owner(parts, owner_ast, cmeta, prefix, scope, ctx, issues)
    visit_children(ast, prefix, scope, ctx, issues)
  end

  # `context |> Context.put_private(owner, value)`, piped.
  defp visit(
         {:|>, _pmeta,
          [_lhs, {{:., _dmeta, [{:__aliases__, _ameta, parts}, :put_private]}, cmeta, [owner_ast, _value_ast]}]} =
           ast,
         prefix,
         scope,
         ctx,
         issues
       ) do
    issues = report_owner(parts, owner_ast, cmeta, prefix, scope, ctx, issues)
    visit_children(ast, prefix, scope, ctx, issues)
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

  # Descend into a matched call's own subtrees, besides the owner argument already handled.

  defp visit_children(
         {{:., _dmeta, [alias_ast, :put_private]}, _cmeta, [ctx_arg, _owner_ast, value_ast]},
         prefix,
         scope,
         ctx,
         issues
       ) do
    issues = visit(alias_ast, prefix, scope, ctx, issues)
    issues = visit(ctx_arg, prefix, scope, ctx, issues)
    visit(value_ast, prefix, scope, ctx, issues)
  end

  defp visit_children(
         {:|>, _pmeta, [lhs, {{:., _dmeta, [alias_ast, :put_private]}, _cmeta, [_owner_ast, value_ast]}]},
         prefix,
         scope,
         ctx,
         issues
       ) do
    issues = visit(alias_ast, prefix, scope, ctx, issues)
    issues = visit(lhs, prefix, scope, ctx, issues)
    visit(value_ast, prefix, scope, ctx, issues)
  end

  defp module_scope(nested_prefix, body, ctx) do
    full_name = ModuleName.full(nested_prefix)

    if own_behaviour?(body, ctx.aliases, ctx.middleware_modules) do
      {:middleware, full_name}
    else
      {:other, full_name}
    end
  end

  defp report_owner(_context_parts, _owner_ast, _cmeta, _prefix, {:other, _}, _ctx, issues), do: issues

  defp report_owner(context_parts, owner_ast, cmeta, _prefix, {:middleware, own_module}, ctx, issues) do
    if MapSet.member?(ctx.context_modules, ModuleName.resolve(context_parts, ctx.aliases)) do
      case foreign_owner(owner_ast, own_module, ctx.aliases) do
        {:foreign, trigger, meta} -> [issue_for(ctx, trigger, meta || cmeta) | issues]
        :self_or_dynamic -> issues
      end
    else
      issues
    end
  end

  defp foreign_owner({:__MODULE__, _meta, nil}, _own_module, _aliases), do: :self_or_dynamic

  defp foreign_owner({:__aliases__, meta, parts}, own_module, aliases) do
    resolved = ModuleName.resolve(parts, aliases)

    if resolved == nil or resolved == own_module do
      :self_or_dynamic
    else
      {:foreign, Name.full(parts), meta}
    end
  end

  defp foreign_owner(_dynamic_ast, _own_module, _aliases), do: :self_or_dynamic

  defp issue_for(ctx, trigger, meta) do
    format_issue(
      ctx.issue_meta,
      message: append_hint(message(trigger), ctx.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp message(trigger) do
    "Name `__MODULE__` as the owner instead of `#{trigger}`, since `put_private/3`'s private " <>
      "slot is namespaced by the module writing to it, and naming another module writes into " <>
      "a slot this middleware does not own."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
