defmodule Trogon.Credo.Check.Dispatcher.ContextMutation do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      middleware_modules: [Trogon.Dispatcher.Middleware],
      handler_modules: [Trogon.Dispatcher.Handler],
      context_modules: [Trogon.Dispatcher.Context],
      except_in: ["Trogon.Dispatcher", "Trogon.Dispatcher.**"],
      hint: nil
    ],
    explanations: [
      check: """
      `Trogon.Dispatcher.Context` carries invariants no module outside the dispatcher is
      meant to break: `message`, `kind`, `dispatcher` and `registered_by` never change
      once the dispatch builds the context, `assigns` stays a map with atom keys, and
      `private` stays a map namespaced by its owning module. The dispatcher only checks
      that a middleware or a handler returns a `Trogon.Dispatcher.Context` and that its
      response fits the contract; it does not check any of these invariants at runtime,
      so a middleware that writes `%{context | assigns: %{"k" => 1}}` compiles, passes
      that check, and corrupts the context for every middleware still ahead of it in the
      pipeline. This check is what stands in for the runtime check the type system cannot
      provide across module boundaries.

      This check reports the struct and map update syntax that reaches past
      `Trogon.Dispatcher.Context.assign/3`, `Context.merge_assigns/2`,
      `Context.put_private/3` and `Context.put_response/2`, inside a module that
      implements `Trogon.Dispatcher.Middleware` or `Trogon.Dispatcher.Handler`.

          # preferred
          def call(context, next, _options) do
            context |> Context.assign(:tenant, tenant) |> next.()
          end

          # NOT preferred
          def call(context, next, _options) do
            %{context | assigns: Map.put(context.assigns, :tenant, tenant)} |> next.()
          end

      Reported: `%{var | assigns: ...}` and the same written with the struct named,
      `%Context{var | assigns: ...}` or `%Trogon.Dispatcher.Context{var | assigns: ...}`,
      for any of `assigns`, `private`, `message`, `kind`, `dispatcher`, `registered_by`
      and `response`; the struct named form is only reported when the name resolves to
      one of `context_modules`, while the unnamed `%{var | ...}` form is reported on the
      field name alone, since the module building it is scoped to a middleware or a
      handler already. `Map.put/3`, `Map.replace!/3` and `struct!/2` are reported the
      same way when the field is a literal atom, a key built at runtime is left alone,
      since there is nothing to resolve statically.

      Not reported: anywhere outside a module that implements one of `middleware_modules`
      or `handler_modules`, a pattern match such as `%Context{assigns: assigns} = context`,
      which reads rather than writes, and the writer functions on `Trogon.Dispatcher.Context`
      itself, together with anything under `except_in`, since that is the dispatcher's own
      namespace and the one place these invariants are implemented.
      """,
      params: [
        middleware_modules: """
        A list of modules that mark a module as a middleware when brought in with
        `@behaviour`. Defaults to `Trogon.Dispatcher.Middleware`.
        """,
        handler_modules: """
        A list of modules that mark a module as a handler when brought in with
        `@behaviour`. Defaults to `Trogon.Dispatcher.Handler`.
        """,
        context_modules: """
        A list of modules that name the context struct. Defaults to
        `Trogon.Dispatcher.Context`; a project that wraps it names the wrapper here
        too, so the named struct update form, `%Context{var | ...}`, is still
        recognized.
        """,
        except_in: """
        A list of module name patterns, in the grammar
        `Trogon.Credo.Check.Design.NamespaceBoundary` documents for `private_to`, read
        against a file's own outermost module. A file whose module matches one of
        these is never scanned. Defaults to `Trogon.Dispatcher` and everything under
        it, the dispatcher's own namespace.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @restricted_fields [:assigns, :private, :message, :kind, :dispatcher, :registered_by, :response]
  @map_functions [:put, :replace!]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    except_in = params |> Params.get(:except_in, __MODULE__) |> List.wrap() |> Enum.map(&ModulePattern.compile!/1)
    own_module = ModuleDeclaration.outermost_module_name(source_file)

    if excepted?(own_module, except_in) do
      []
    else
      aliases = ModuleName.collect_aliases(source_file)

      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        aliases: aliases,
        markers: markers(params, :middleware_modules, :handler_modules),
        context_modules: markers(params, :context_modules),
        hint: Params.get(params, :hint, __MODULE__)
      }

      source_file
      |> SourceFile.ast()
      |> visit(:other, context, [])
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

  defp markers(params, key_a, key_b), do: MapSet.union(markers(params, key_a), markers(params, key_b))

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

  defp visit({:defmodule, _meta, [{:__aliases__, _ameta, parts}, body]}, _scope, ctx, issues) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      scope = if own_behaviour?(body, ctx.aliases, ctx.markers), do: :context_owner, else: :other
      visit(body, scope, ctx, issues)
    else
      visit(body, :other, ctx, issues)
    end
  end

  defp visit({:defmodule, _meta, [_name, body]}, _scope, ctx, issues) do
    visit(body, :other, ctx, issues)
  end

  defp visit({:quote, _meta, _args}, _scope, _ctx, issues), do: issues

  defp visit({:@, _meta, [{attr_kind, _ameta, _attr_args}]}, _scope, _ctx, issues)
       when attr_kind in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    issues
  end

  # `%{var | assigns: ...}`, the unnamed map update form.
  defp visit({:%{}, _meta, [{:|, update_meta, [var, pairs]}]}, scope, ctx, issues) when is_list(pairs) do
    issues = report_fields(scope, ctx, pairs, "|", update_meta, issues)
    visit([var, pairs], scope, ctx, issues)
  end

  # `%Context{var | assigns: ...}` / `%Trogon.Dispatcher.Context{var | assigns: ...}`,
  # the named struct update form.
  defp visit(
         {:%, _meta, [{:__aliases__, _alias_meta, struct_parts}, {:%{}, _map_meta, [{:|, update_meta, [var, pairs]}]}]},
         scope,
         ctx,
         issues
       )
       when is_list(pairs) do
    issues =
      if MapSet.member?(ctx.context_modules, ModuleName.resolve(struct_parts, ctx.aliases)) do
        report_fields(scope, ctx, pairs, "|", update_meta, issues)
      else
        issues
      end

    visit([var, pairs], scope, ctx, issues)
  end

  # `Map.put(context, :assigns, value)` / `Map.replace!(context, :private, value)`.
  defp visit(
         {{:., _dmeta, [{:__aliases__, _mmeta, [:Map]}, function]}, cmeta, [subject, key, value]},
         scope,
         ctx,
         issues
       )
       when function in @map_functions and is_atom(key) do
    issues = report_fields(scope, ctx, [{key, value}], Atom.to_string(function), cmeta, issues)
    visit([subject, value], scope, ctx, issues)
  end

  # `context |> Map.put(:assigns, value)` / `context |> Map.replace!(:private, value)`.
  defp visit(
         {:|>, _pmeta, [subject, {{:., _dmeta, [{:__aliases__, _mmeta, [:Map]}, function]}, cmeta, [key, value]}]},
         scope,
         ctx,
         issues
       )
       when function in @map_functions and is_atom(key) do
    issues = report_fields(scope, ctx, [{key, value}], Atom.to_string(function), cmeta, issues)
    visit([subject, value], scope, ctx, issues)
  end

  # `context |> struct!(assigns: value)`.
  defp visit({:|>, _pmeta, [subject, {:struct!, meta, [fields]}]}, scope, ctx, issues) do
    visit_struct!(subject, fields, "struct!", meta, scope, ctx, issues)
  end

  # `context |> Kernel.struct!(assigns: value)`.
  defp visit(
         {:|>, _pmeta, [subject, {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, :struct!]}, cmeta, [fields]}]},
         scope,
         ctx,
         issues
       ) do
    visit_struct!(subject, fields, "struct!", cmeta, scope, ctx, issues)
  end

  # `struct!(context, assigns: value)`, the field a map literal or a keyword list.
  defp visit({:struct!, meta, [subject, fields]}, scope, ctx, issues) do
    visit_struct!(subject, fields, "struct!", meta, scope, ctx, issues)
  end

  # `Kernel.struct!(context, assigns: value)`.
  defp visit(
         {{:., _dmeta, [{:__aliases__, _kmeta, [:Kernel]}, :struct!]}, cmeta, [subject, fields]},
         scope,
         ctx,
         issues
       ) do
    visit_struct!(subject, fields, "struct!", cmeta, scope, ctx, issues)
  end

  defp visit({form, _meta, args}, scope, ctx, issues) when is_list(args) do
    issues = if is_tuple(form), do: visit(form, scope, ctx, issues), else: issues
    visit(args, scope, ctx, issues)
  end

  defp visit({left, right}, scope, ctx, issues) do
    visit(right, scope, ctx, visit(left, scope, ctx, issues))
  end

  defp visit(list, scope, ctx, issues) when is_list(list) do
    Enum.reduce(list, issues, &visit(&1, scope, ctx, &2))
  end

  defp visit(_ast, _scope, _ctx, issues), do: issues

  defp visit_struct!(subject, fields, trigger, meta, scope, ctx, issues) do
    issues =
      case literal_pairs(fields) do
        {:ok, pairs} -> report_fields(scope, ctx, pairs, trigger, meta, issues)
        :error -> issues
      end

    visit([subject, fields], scope, ctx, issues)
  end

  defp literal_pairs(pairs) when is_list(pairs), do: {:ok, pairs}
  defp literal_pairs({:%{}, _meta, pairs}) when is_list(pairs), do: {:ok, pairs}
  defp literal_pairs(_other), do: :error

  defp report_fields(:other, _ctx, _pairs, _trigger, _meta, issues), do: issues

  defp report_fields(:context_owner, ctx, pairs, trigger, meta, issues) do
    pairs
    |> Enum.filter(&restricted_pair?/1)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Enum.reduce(issues, &[issue_for(ctx, &1, trigger, meta) | &2])
  end

  defp restricted_pair?({key, _value}) when is_atom(key), do: key in @restricted_fields
  defp restricted_pair?(_pair), do: false

  defp issue_for(ctx, field, trigger, meta) do
    format_issue(
      ctx.issue_meta,
      message: append_hint(message_for(field), ctx.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp message_for(:assigns) do
    "Write to `assigns` through `Trogon.Dispatcher.Context.assign/3` or " <>
      "`Trogon.Dispatcher.Context.merge_assigns/2` instead of updating the struct directly."
  end

  defp message_for(:private) do
    "Write to `private` through `Trogon.Dispatcher.Context.put_private/3` instead of updating the struct directly."
  end

  defp message_for(:response) do
    "Set `response` through `Trogon.Dispatcher.Context.put_response/2` instead of updating the struct directly."
  end

  defp message_for(field) do
    "`#{field}` is set by the dispatch and never changed; updating it directly breaks the context's invariants."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
