defmodule Trogon.Credo.Check.Dispatcher.StructConstruction do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      dispatch_options_modules: [Trogon.Dispatcher.DispatchOptions],
      context_modules: [Trogon.Dispatcher.Context],
      except_in: ["Trogon.Dispatcher", "Trogon.Dispatcher.**"],
      hint: nil
    ],
    explanations: [
      check: """
      `Trogon.Dispatcher.DispatchOptions.new/1` and `Trogon.Dispatcher.Context.new/3` are the
      only places these two structs' invariants are checked: `new/1` rejects an unknown key,
      and `Context.new/3` fills in `kind`, `dispatcher` and `registered_by` from the dispatch
      that is actually in flight. None of that runs when a caller writes the struct literal
      directly, so `%DispatchOptions{assigns: "nope"}` and `%Context{kind: :not_a_kind,
      dispatcher: nil, registered_by: nil}` both compile clean and skip every invariant the
      smart constructor would have held.

      This check reports a struct literal naming one of `dispatch_options_modules` or
      `context_modules` anywhere outside `except_in`.

          # preferred
          {:ok, options} = DispatchOptions.new(actor: actor, assigns: %{request_id: id})
          context = Context.new(message, options, dispatcher: MyApp.Dispatcher)

          # NOT preferred
          options = %DispatchOptions{actor: actor, assigns: %{request_id: id}}
          context = %Context{message: message, kind: :command, dispatcher: nil, registered_by: nil}

      Reported: `%DispatchOptions{...}` and `%Context{...}`, written bare or fully qualified as
      `%Trogon.Dispatcher.DispatchOptions{...}` / `%Trogon.Dispatcher.Context{...}`, in
      expression position. The message names `DispatchOptions.new/1` or `new!/1` for the
      former, and `Context.new/3`, or `Trogon.Dispatcher.Test`'s `build_context/3` in a test,
      for the latter.

      Not reported: a pattern, such as a function head, a `case`/`with` clause, or the left
      side of a `=`, since a pattern matches a value rather than building one; the struct
      update form, `%Context{context | ...}`, since it already has a valid struct to start
      from and nothing there skips a constructor, `Trogon.Credo.Check.Dispatcher.ContextMutation`
      is what covers what it writes instead; and anything under `except_in`, since that is the
      dispatcher's own namespace, the one place these two structs are legitimately built
      directly, `Context.to_dispatch_options/1` in particular.
      """,
      params: [
        dispatch_options_modules: """
        A list of modules whose struct literal is reported, suggesting `new/1` or `new!/1`.
        Defaults to `Trogon.Dispatcher.DispatchOptions`.
        """,
        context_modules: """
        A list of modules whose struct literal is reported, suggesting `new/3`, or
        `Trogon.Dispatcher.Test` in a test. Defaults to `Trogon.Dispatcher.Context`.
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
  alias Trogon.Credo.AstPattern
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
        dispatch_options_modules: markers(params, :dispatch_options_modules),
        context_modules: markers(params, :context_modules),
        test_file?: String.ends_with?(source_file.filename, "_test.exs"),
        hint: Params.get(params, :hint, __MODULE__)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context))
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

  defp traverse({:@, _meta, [{attr_kind, _ameta, _attr_args}]}, issues, _context)
       when attr_kind in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    {[], issues}
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  # `%Context{var | ...}`, the struct update form, already has a valid struct to update and is
  # not a construction; `ContextMutation` covers what it writes.
  defp traverse(
         {:%, _meta, [{:__aliases__, _ameta, _parts}, {:%{}, _mmeta, [{:|, _umeta, [_var, _pairs]}]}]} = ast,
         issues,
         _context
       ) do
    {ast, issues}
  end

  defp traverse({:%, _meta, [{:__aliases__, ameta, parts}, {:%{}, _mmeta, fields}]} = ast, issues, context)
       when is_list(fields) do
    {ast, report(ModuleName.resolve(parts, context.aliases), parts, ameta, context, issues)}
  end

  defp traverse(ast, issues, _context) do
    case AstPattern.hide_pattern_position(ast) do
      {:ok, rewritten} -> {rewritten, issues}
      :error -> {ast, issues}
    end
  end

  defp report(nil, _parts, _meta, _context, issues), do: issues

  defp report(resolved, parts, meta, context, issues) do
    cond do
      MapSet.member?(context.dispatch_options_modules, resolved) ->
        [issue_for(context, parts, meta, dispatch_options_message()) | issues]

      MapSet.member?(context.context_modules, resolved) ->
        [issue_for(context, parts, meta, context_message(context.test_file?)) | issues]

      true ->
        issues
    end
  end

  defp issue_for(context, parts, meta, message) do
    format_issue(
      context.issue_meta,
      message: append_hint(message, context.hint),
      trigger: Name.full(parts),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp dispatch_options_message do
    "Build it with `Trogon.Dispatcher.DispatchOptions.new/1` or `new!/1` instead of writing " <>
      "the struct literal directly, so an unknown key is rejected instead of silently carried."
  end

  defp context_message(true) do
    "Build it with `Trogon.Dispatcher.Context.new/3`, or with `Trogon.Dispatcher.Test`'s " <>
      "`build_context/3` in a test, instead of writing the struct literal directly."
  end

  defp context_message(false) do
    "Build it with `Trogon.Dispatcher.Context.new/3` instead of writing the struct literal directly."
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
