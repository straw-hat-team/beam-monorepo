defmodule Trogon.Credo.Check.Warning.ForbiddenFunctionCall do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      calls: [],
      hint: nil
    ],
    explanations: [
      check: """
      Some calls are dangerous only in a specific part of a codebase: wall clock time
      or randomness inside a layer required to stay deterministic, for instance, while
      every other use of the same module stays fine elsewhere.

      Credo ships `Credo.Check.Warning.ForbiddenModule` to forbid a module altogether.
      This check is the call site counterpart: it reports a call rather than a written
      name, so a project can forbid `System.get_env/1` without forbidding `System`.

          {Trogon.Credo.Check.Warning.ForbiddenFunctionCall,
           [calls: [
              {System, :get_env},
              {{Process, :sleep}, "Use a scheduled job instead of sleeping."},
              {:rand, "Randomness must be supplied to this layer, not drawn inside it."}
            ]]}

      The configuration above forbids `System.get_env/1` with the default message,
      `Process.sleep/1` with a custom one, and every function on `:rand`. An entry
      naming a module on its own covers every call to that module, which is how a
      project says that none of it belongs in a layer, and is the one way to say that
      about an Erlang module, since `Credo.Check.Warning.ForbiddenModule` reads written
      aliases. `Kernel` cannot be named on its own, since it is auto imported into every
      module, which would make the entry report every call in the file; such an entry
      raises, and the functions have to be named instead.

      Scoping a rule to a single layer is done through Credo's own per check `files:`
      param. Arity is deliberately not part of an entry, so every arity of the named
      function is reported: a project that forbids `Process.sleep` means all of it.

      `Module` may be an Elixir module or an Erlang module given as a plain atom, `:os`
      or `:rand` for instance. Both a qualified call, `System.get_env("HOME")`, and a
      captured one, `&System.get_env/1`, are reported, since a capture is a call site
      for this purpose just as much as an invocation is. A module written with an
      explicit `Elixir.` prefix names the same module and is reported the same way.
      Aliases are resolved before matching, and a name the file binds to two different
      modules matches neither.

      An unqualified call is reported only for a `Kernel` entry, since `Kernel` is the
      one module auto imported into every module, so `{Kernel, :dbg}` reports a bare
      `dbg(value)` as well as `Kernel.dbg(value)`. For any other module the check
      cannot know, from a single file, whether a bare `get_env(...)` came from an
      `import` or is simply a local function, so it is never reported. An unqualified
      capture, `&dbg/1` for instance, is not reported either, even for a `Kernel`
      entry, since a bare capture carries no module for the check to read.

      Not reported: a module named in a typespec, which is not a call to it; a module
      named in an `alias`, `import`, `require`, or `use` directive, including the multi
      alias form `System.{Foo}` that shares its AST shape with a call; anything written
      inside such a directive, so a call in a `use` option stays silent as well; the
      name in a function head, a `defdelegate` head included, since defining a function
      is not calling one; and a function of the same name defined on a different,
      unconfigured module.
      """,
      params: [
        calls: """
        A list of entries naming what must not be called. An entry is a
        `{Module, :function}` tuple, a `Module` on its own to cover every
        function on it, or either of those paired with a custom message, as
        `{{Module, :function}, "Custom message"}` or `{Module, "Custom
        message"}`. `Module` may be an Elixir module or an Erlang module given
        as a plain atom, except that `Kernel` may not be named on its own.
        Every arity of the named function is covered by a single entry. The
        default empty list makes the check inert, since there is no universal
        forbidden call.
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

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]
  @directives [:alias, :import, :require, :use]
  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]
  @kernel_module "Kernel"

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    {calls, modules} = prepare_calls(Params.get(params, :calls, __MODULE__))

    if calls == %{} and modules == %{} do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        calls: calls,
        modules: modules,
        hint: Params.get(params, :hint, __MODULE__),
        aliases: ModuleName.collect_aliases(source_file)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    end
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _context)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  defp traverse({directive, _meta, args}, issues, _context)
       when directive in @directives and is_list(args) do
    {[], issues}
  end

  defp traverse({kind, _meta, [{:when, _, [head, guard]} | rest]}, issues, _context)
       when kind in @definition_kinds do
    {[head_args(head), guard | rest], issues}
  end

  defp traverse({kind, _meta, [head | rest]}, issues, _context)
       when kind in @definition_kinds do
    {[head_args(head) | rest], issues}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, alias_meta, parts}, function]}, _call_meta, args} = ast,
         issues,
         context
       )
       when is_atom(function) and is_list(args) do
    module = ModuleName.resolve(parts, context.aliases)
    trigger = "#{Name.full(parts)}.#{function}"

    {ast, report(context, module, function, trigger, alias_meta, issues)}
  end

  defp traverse({{:., dot_meta, [module, function]}, _call_meta, args} = ast, issues, context)
       when is_atom(module) and is_atom(function) and is_list(args) do
    written_module = inspect(module)
    trigger = "#{written_module}.#{function}"
    meta = erlang_call_meta(dot_meta, written_module)

    {ast, report(context, ModuleName.full(module), function, trigger, meta, issues)}
  end

  defp traverse({function, call_meta, args} = ast, issues, context)
       when is_atom(function) and is_list(args) do
    {ast, report(context, @kernel_module, function, to_string(function), call_meta, issues)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp head_args({_name, _meta, args}) when is_list(args), do: args
  defp head_args(_head), do: []

  # An Erlang module written as a plain atom carries no meta of its own, so the
  # column of the call site is derived from the dot's column, which always
  # immediately follows the module name in valid syntax.
  defp erlang_call_meta(dot_meta, written_module) do
    Keyword.update(dot_meta, :column, nil, fn column -> column - String.length(written_module) end)
  end

  defp report(_context, nil, _function, _trigger, _call_meta, issues), do: issues

  defp report(context, module, function, trigger, call_meta, issues) do
    case forbidden_entry(context, module, function) do
      {:ok, {message, display}} ->
        [issue_for(context, call_meta, trigger, display, function, message) | issues]

      :error ->
        issues
    end
  end

  defp forbidden_entry(context, module, function) do
    case Map.fetch(context.calls, {module, function}) do
      {:ok, entry} -> {:ok, entry}
      :error -> Map.fetch(context.modules, module)
    end
  end

  defp issue_for(context, meta, trigger, display, function, message) do
    default_message = "The `#{display}.#{function}` function must not be called."

    format_issue(
      context.issue_meta,
      message: append_hint(message || default_message, context.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"

  defp prepare_calls(calls) do
    {call_entries, module_entries} =
      calls
      |> Enum.map(&normalize_call/1)
      |> Enum.split_with(fn {key, _entry} -> is_tuple(key) end)

    {Map.new(call_entries), Map.new(module_entries)}
  end

  defp normalize_call({{module, function}, message}) when is_atom(module) and is_atom(function) do
    {{module_key(module), function}, {message, module_display(module)}}
  end

  defp normalize_call({module, function}) when is_atom(module) and is_atom(function) do
    {{module_key(module), function}, {nil, module_display(module)}}
  end

  defp normalize_call({module, message}) when is_atom(module) and is_binary(message) do
    {whole_module_key(module), {message, module_display(module)}}
  end

  defp normalize_call(module) when is_atom(module) do
    {whole_module_key(module), {nil, module_display(module)}}
  end

  defp normalize_call(entry) do
    raise ArgumentError,
          "invalid calls entry #{inspect(entry)}: expected Module, {Module, :function}, " <>
            "or either of those paired with a message"
  end

  defp whole_module_key(module) do
    case module_key(module) do
      @kernel_module ->
        raise ArgumentError,
              "invalid calls entry #{inspect(module)}: `Kernel` cannot be forbidden as a whole " <>
                "module, since it is auto imported into every module, so name its functions instead"

      key ->
        key
    end
  end

  defp module_key(module), do: ModuleName.full(module)

  defp module_display(module) do
    case Atom.to_string(module) do
      "Elixir." <> _ -> ModuleName.full(module)
      _ -> inspect(module)
    end
  end
end
