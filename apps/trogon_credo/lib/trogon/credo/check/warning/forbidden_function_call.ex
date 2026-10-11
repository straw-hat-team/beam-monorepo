defmodule Trogon.Credo.Check.Warning.ForbiddenFunctionCall do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      calls: [],
      except: [],
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
              {:rand, "Randomness must be supplied to this layer, not drawn inside it."},
              {"Acme.**.Domain.**Error", :new}
            ]]}

      The configuration above forbids `System.get_env/1` with the default message,
      `Process.sleep/1` with a custom one, every function on `:rand`, and `new` on every
      module whose name matches `Acme.**.Domain.**Error`. An entry
      naming a module on its own covers every call to that module, which is how a
      project says that none of it belongs in a layer, and works on an Erlang module as
      well, which `Credo.Check.Warning.ForbiddenModule` cannot say, since it reads
      written aliases. `Kernel` cannot be named on its own, since it is auto imported into every
      module, which would make the entry report every call in the file; such an entry
      raises, and the functions have to be named instead.

      A module is named either by its name or by a pattern, given as a string, which
      covers every module the pattern matches, so a rule over a namespace is written
      once rather than once per module. `{"Acme.**.Domain.**Error", :new}` forbids
      `new` on every domain error module, and `"Acme.Legacy.**"` on its own forbids
      every call into that namespace. The pattern grammar is the one
      `Trogon.Credo.Check.Design.NamespaceBoundary` documents: a fully qualified module
      name, anchored at both ends, with `*` matching within a segment and `**` across
      them. A pattern that matches `Kernel` cannot name a whole module either, and
      raises the same way. An issue from a pattern entry names the module the call
      resolved to, so an Erlang module reads as the atom it is written as.

      An entry that covers more than a project means carves the part it allows out with
      `except`, which takes the same entries without their messages.

          {Trogon.Credo.Check.Warning.ForbiddenFunctionCall,
           [calls: ["Acme.Legacy.**"],
            except: [{Acme.Legacy.Client, :fetch}]]}

      With the configuration above every call into the legacy namespace is reported
      except `Acme.Legacy.Client.fetch`, which is how a project forbids a namespace
      while it still has one supported way in. An `except` entry naming a module on its
      own allows every call to it, and `except` on its own, with nothing in `calls`,
      leaves the check inert.

      Scoping a rule to a single layer is done through Credo's own per check `files:`
      param. An entry may name an arity, as `{Process, :sleep, 1}`, and then covers that
      arity alone, which is what a project that objects to one of several ways to call a
      function needs. An entry without an arity covers every arity the function has,
      which is what forbidding a function usually means.

      An arity is read from the call as Elixir makes it, so a capture names the arity it
      is written with, `&System.get_env/1` being arity one, and a piped call counts the
      argument the pipe supplies.

      `Module` may be an Elixir module or an Erlang module given as a plain atom, `:os`
      or `:rand` for instance. Both a qualified call, `System.get_env("HOME")`, and a
      captured one, `&System.get_env/1`, are reported, since a capture is a call site
      for this purpose just as much as an invocation is. A module written with an
      explicit `Elixir.` prefix names the same module and is reported the same way.
      Aliases are resolved before matching, and a name the file binds to two different
      modules matches neither.

      An unqualified call is read against what the file imports, plus `Kernel`, which
      every module imports on its own. `{Kernel, :dbg}` reports a bare `dbg(value)` as
      well as `Kernel.dbg(value)`, and `{System, :get_env}` reports a bare
      `get_env("HOME")` in a file that writes `import System`, since Elixir refuses to
      compile a local function that conflicts with an import, so the name cannot be
      anything else. A file that takes a name back from `Kernel` with an `except:`
      option is read the same way, and its own `dbg(value)` is left alone, as is a
      file whose `import Kernel, only:` leaves that name out, since such an import
      replaces the automatic one. A multi form directive, `import System.{Env}`, is
      read as an import of each module it lists.

      An `import` is read where Elixir scopes it, so a call is read against what the
      block it is written in imports, together with whatever encloses that block. A
      call in a sibling module, in a clause beside the one that wrote the directive, or
      after the anonymous function that wrote it, is not read against it.

      A directive selects by name and arity, so a call at an arity it leaves out is not
      the imported function. An unrestricted directive names no arity of its own, so a
      bare call is read against what the module exports, and a call at an arity the
      module does not have is a local function of the same name, except for a special
      form, which is read by the name alone, since a form such as `for` takes as many
      arguments as it is written with. A module the check
      cannot load, one that only exists in another environment for instance, is read as
      bringing the name in, so a rule is not stepped around by a module the check cannot
      see. A piped call counts the argument the pipe supplies, since that is the call
      Elixir makes. Two directives naming one module are read the way
      Elixir reads them: a later `only:` replaces what an earlier one brought in, while
      `except:` filters what is already there.

      An entry naming a module on its own reaches a bare call only where an `import`
      lists the function in `only:`. An unrestricted `import` does not say which names
      it brings in, and reporting every bare call in the file on that basis would name
      calls the module has nothing to do with. An unqualified capture, `&dbg/1` for
      instance, is not reported, since a bare capture carries no module for the check
      to read.

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
        message"}`. An entry may name an arity, as `{Module, :function,
        arity}`, to cover that arity alone rather than every arity of the
        function. `Module` may be an Elixir module, an Erlang module given as
        a plain atom, or a module name pattern given as a string, which covers
        every module it matches, except that `Kernel` may not be named on its
        own, by name or by a pattern that matches it.
        Every arity of the named function is covered by a single entry. The
        default empty list makes the check inert, since there is no universal
        forbidden call.
        """,
        except: """
        A list of entries that carve exceptions out of `calls`. A call matching
        any of them is never reported, even when it also matches a forbidden
        entry. The entry forms are the ones `calls` takes, arity included and
        without their `{entry, "message"}` form, since an exception reports nothing and so has
        no message to carry, and `Kernel` may be named on its own here. The
        default empty list means there is no exception; `nil` is also accepted
        and treated the same way.
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
  alias Trogon.Credo.ModulePattern

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]
  @directives [:alias, :import, :require, :use]
  @definition_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]
  @kernel_module "Kernel"
  @special_forms Enum.uniq(Keyword.keys(Kernel.SpecialForms.__info__(:macros)))
  @block_keys [:do, :else, :rescue, :after, :catch]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    calls = prepare_calls(Params.get(params, :calls, __MODULE__))

    if configured?(calls) do
      aliases = ModuleName.collect_aliases(source_file)

      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        calls: calls,
        except: prepare_except(Params.get(params, :except, __MODULE__) || []),
        hint: Params.get(params, :hint, __MODULE__),
        aliases: aliases,
        imports: collect_imports(source_file, aliases)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    else
      []
    end
  end

  defp configured?(calls) do
    Enum.any?(calls, fn {_kind, entries} -> not Enum.empty?(entries) end)
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

  # A capture names the function it captures at an arity of its own, and the call
  # written inside it carries no arguments, so the arity is read from the capture
  # and the call is left out of the walk.
  defp traverse({:&, _meta, [{:/, _, [{{:., _, [_module, _function]}, _, []} = call, arity]}]}, issues, context)
       when is_integer(arity) do
    {[], report_qualified(context, call, arity, issues)}
  end

  # A piped call is written without its first argument, so a qualified one is
  # reported at the arity the pipe gives it and left out of the walk, the way a
  # bare piped call is.
  defp traverse({:|>, _meta, [left, {{:., _, [_module, _function]}, _, args} = call]}, issues, context)
       when is_list(args) do
    {[left | args], report_qualified(context, call, length(args) + 1, issues)}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, _parts}, function]}, _call_meta, args} = ast,
         issues,
         context
       )
       when is_atom(function) and is_list(args) do
    {ast, report_qualified(context, ast, length(args), issues)}
  end

  # A piped call is written without its first argument, so the node carries one
  # argument fewer than the call has, and reading its arity as written would miss
  # what the file imports. The call is reported here and left out of the walk, so
  # the clause that reads a bare call never sees it.
  defp traverse({:|>, _meta, [left, {function, call_meta, args}]}, issues, context)
       when is_atom(function) and function != :|> and (is_list(args) or is_nil(args)) do
    piped_args = List.wrap(args)
    issues = report_unqualified(context, function, length(piped_args) + 1, call_meta, issues)

    {[left | piped_args], issues}
  end

  defp traverse({{:., _dot_meta, [module, function]}, _call_meta, args} = ast, issues, context)
       when is_atom(module) and is_atom(function) and is_list(args) do
    {ast, report_qualified(context, ast, length(args), issues)}
  end

  defp traverse({function, call_meta, args} = ast, issues, context)
       when is_atom(function) and is_list(args) do
    {ast, report_unqualified(context, function, length(args), call_meta, issues)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp head_args({_name, _meta, args}) when is_list(args), do: args
  defp head_args(_head), do: []

  defp report_qualified(
         context,
         {{:., _dot_meta, [{:__aliases__, alias_meta, parts}, function]}, _call_meta, _args},
         arity,
         issues
       )
       when is_atom(function) do
    module = ModuleName.resolve(parts, context.aliases)
    trigger = "#{Name.full(parts)}.#{function}"

    report(context, module, function, arity, trigger, alias_meta, issues)
  end

  defp report_qualified(context, {{:., dot_meta, [module, function]}, _call_meta, _args}, arity, issues)
       when is_atom(module) and is_atom(function) do
    written_module = inspect(module)
    trigger = "#{written_module}.#{function}"
    meta = erlang_call_meta(dot_meta, written_module)

    report(context, ModuleName.full(module), function, arity, trigger, meta, issues)
  end

  defp report_qualified(_context, _call, _arity, issues), do: issues

  # An Erlang module written as a plain atom carries no meta of its own, so the
  # column of the call site is derived from the dot's column, which always
  # immediately follows the module name in valid syntax.
  defp erlang_call_meta(dot_meta, written_module) do
    Keyword.update(dot_meta, :column, nil, fn column -> column - String.length(written_module) end)
  end

  defp report_unqualified(context, function, arity, call_meta, issues) do
    states = imports_in_scope(context.imports, call_meta[:line])
    candidates = import_candidates(states, function, arity) ++ kernel_candidate(states)

    case Enum.find_value(candidates, &unqualified_entry(context, &1, function, arity)) do
      nil ->
        issues

      {message, display} ->
        [issue_for(context, call_meta, to_string(function), display, function, message) | issues]
    end
  end

  # A name an `import` lists in `only:` is known to come from that module, so an
  # entry naming the module as a whole covers it too. An unrestricted `import`
  # says nothing about which names it brings in, so only an entry naming the
  # function applies, which a local function of that name cannot be, since
  # Elixir refuses to compile a local definition that conflicts with an import.
  defp unqualified_entry(context, {module, :only}, function, arity) do
    case forbidden_entry(context, module, function, arity) do
      {:ok, entry} -> entry
      :error -> nil
    end
  end

  defp unqualified_entry(context, {module, :open}, function, arity) do
    case function_entry(context.calls, module, function, arity) do
      {:ok, entry} ->
        if imported_name?(module, function, arity) and not excepted?(context, module, function, arity) do
          resolve_display(entry, module)
        end

      :error ->
        nil
    end
  end

  # An unrestricted `import` brings in what the module exports, so a bare call at
  # an arity the module does not have is a local function that happens to share
  # the name rather than the imported one. A module the check cannot load is read
  # as bringing the name in, so a rule is not stepped around by a module that is
  # only there in another environment.
  defp imported_name?(module, function, arity) do
    target = module_atom(module)

    if Code.ensure_loaded?(target) do
      exported?(target, function, arity)
    else
      true
    end
  end

  defp module_atom(<<first, _rest::binary>> = module) when first in ?a..?z do
    String.to_atom(module)
  end

  defp module_atom(module), do: Module.concat([module])

  # Elixir's automatic import brings in `Kernel` and `Kernel.SpecialForms`, so a
  # special form is read against the entry that names `Kernel`. Arity plays no
  # part there: a form takes as many arguments as it is written with, `for` with
  # two generators for instance, and the call site is the form even in a module
  # that defines a function of the same name, which is what makes reading the
  # name alone right here.
  defp exported?(Kernel, function, arity) do
    exports?(Kernel, function, arity) or function in @special_forms
  end

  defp exported?(module, function, arity), do: exports?(module, function, arity)

  defp exports?(module, function, arity) do
    Code.ensure_loaded?(module) and
      (function_exported?(module, function, arity) or macro_exported?(module, function, arity))
  end

  # An `import` selects by name and arity, so a call at an arity the directive
  # leaves out is not the imported function, whichever way the selection is
  # written.
  defp import_candidates(states, function, arity) do
    Enum.flat_map(states, &import_candidate(&1, function, arity))
  end

  defp import_candidate({module, {:only, pairs}}, function, arity) do
    if {function, arity} in pairs do
      [{module, :only}]
    else
      []
    end
  end

  defp import_candidate({module, {:open, excluded}}, function, arity) do
    if {function, arity} in excluded do
      []
    else
      [{module, :open}]
    end
  end

  # `Kernel` is auto imported, so a bare call is attributed to it unless the file
  # writes an `import Kernel` of its own, which then says on its own which names
  # come from there.
  defp kernel_candidate(states) do
    if Map.has_key?(states, @kernel_module) do
      []
    else
      [{@kernel_module, :open}]
    end
  end

  # An `import` is lexically scoped, so it is read only for a call written inside
  # the block that declares it, which is what keeps a module from being read
  # against what a sibling module in the same file imports, and what lets a
  # nested module be read against what encloses it.
  defp imports_in_scope(imports, line) do
    imports
    |> Enum.filter(&in_scope?(&1, line))
    |> Enum.sort_by(&scope_start/1)
    |> Enum.reduce(%{}, &put_effective/2)
  end

  defp in_scope?({_module, _selector, {from, to}}, line) when is_integer(line) do
    line >= from and line <= to
  end

  defp in_scope?(_import, _line), do: true

  defp scope_start({_module, _selector, {from, _to}}), do: from

  defp put_effective({module, selector, _lines}, states) do
    Map.put(states, module, effective(Map.get(states, module), selector))
  end

  # A second `import` of the same module replaces what the first one brought in,
  # while `except:` filters what is already there rather than replacing it, which
  # is how Elixir reads a pair of directives naming one module.
  defp effective(_previous, :all), do: {:open, []}
  defp effective(_previous, {:only, pairs}), do: {:only, pairs}
  defp effective(nil, {:except, pairs}), do: {:open, pairs}
  defp effective({:only, pairs}, {:except, excluded}), do: {:only, pairs -- excluded}
  defp effective({:open, excluded}, {:except, pairs}), do: {:open, excluded ++ pairs}

  defp collect_imports(source_file, aliases) do
    ast = SourceFile.ast(source_file)

    scoped_imports(ast, aliases, max_line(ast))
  end

  defp scoped_imports({:quote, _meta, _args}, _aliases, _scope_end), do: []

  defp scoped_imports({:import, meta, [target | opts]}, aliases, scope_end) do
    Enum.map(import_entries(target, opts, aliases), &scope_lines(&1, meta[:line], scope_end))
  end

  defp scoped_imports({:->, _meta, [head, body]}, aliases, _scope_end) do
    scoped_imports(head, aliases, max_line(head)) ++ scoped_imports(body, aliases, max_line(body))
  end

  defp scoped_imports({form, _meta, args}, aliases, scope_end) when is_list(args) do
    {blocks, rest} = split_blocks(args)

    scoped_imports([form | rest], aliases, scope_end) ++ scoped_blocks(blocks, aliases)
  end

  defp scoped_imports({left, right}, aliases, scope_end) do
    scoped_imports([left, right], aliases, scope_end)
  end

  defp scoped_imports(nodes, aliases, scope_end) when is_list(nodes) do
    Enum.flat_map(nodes, &scoped_imports(&1, aliases, scope_end))
  end

  defp scoped_imports(_ast, _aliases, _scope_end), do: []

  defp scope_lines({module, selector}, line, scope_end) do
    {module, selector, {line || 0, scope_end}}
  end

  # Each block of a form is its own scope, so an `import` written in one of them
  # reaches neither a sibling block nor whatever follows the form.
  defp split_blocks(args) do
    case List.last(args) do
      [_entry | _rest] = blocks -> split_block_args(args, blocks)
      _other -> {[], args}
    end
  end

  defp split_block_args(args, blocks) do
    case Enum.split_with(blocks, &block_entry?/1) do
      {[], _options} -> {[], args}
      {block_entries, options} -> {block_entries, Enum.drop(args, -1) ++ [options]}
    end
  end

  defp block_entry?({key, _body}) when key in @block_keys, do: true
  defp block_entry?(_entry), do: false

  defp scoped_blocks(blocks, aliases) do
    Enum.flat_map(blocks, &scoped_block(&1, aliases))
  end

  defp scoped_block({_key, body}, aliases) do
    scoped_imports(body, aliases, max_line(body))
  end

  defp max_line(ast) do
    {_ast, line} = Macro.prewalk(ast, 0, &highest_line/2)

    line
  end

  defp highest_line({_form, meta, _args} = node, line) when is_list(meta) do
    {node, max(line, meta[:line] || 0)}
  end

  defp highest_line(node, line), do: {node, line}

  defp import_entries(target, opts, aliases) do
    selector = import_selector(opts)

    target
    |> import_modules(aliases)
    |> Enum.map(&{&1, selector})
  end

  defp import_modules({{:., _, [{:__aliases__, _, base_parts}, :{}]}, _, member_nodes}, aliases) do
    Enum.flat_map(member_nodes, &member_module(&1, base_parts, aliases))
  end

  defp import_modules({:__aliases__, _meta, parts}, aliases) do
    List.wrap(ModuleName.resolve(parts, aliases))
  end

  defp import_modules(module, _aliases) when is_atom(module), do: [ModuleName.full(module)]
  defp import_modules(_target, _aliases), do: []

  defp member_module({:__aliases__, _meta, member_parts}, base_parts, aliases) do
    List.wrap(ModuleName.resolve(base_parts ++ member_parts, aliases))
  end

  defp member_module(_member, _base_parts, _aliases), do: []

  defp import_selector([opts]) when is_list(opts) do
    case Keyword.fetch(opts, :only) do
      {:ok, only} when is_list(only) -> {:only, function_pairs(only)}
      {:ok, _functions_or_macros} -> :all
      :error -> except_selector(opts)
    end
  end

  defp import_selector(_opts), do: :all

  defp except_selector(opts) do
    case Keyword.fetch(opts, :except) do
      {:ok, except} when is_list(except) -> {:except, function_pairs(except)}
      _other -> :all
    end
  end

  defp function_pairs(entries) do
    Enum.flat_map(entries, &function_pair/1)
  end

  defp function_pair({name, arity}) when is_atom(name) and is_integer(arity), do: [{name, arity}]
  defp function_pair(_entry), do: []

  defp report(_context, nil, _function, _arity, _trigger, _call_meta, issues), do: issues

  defp report(context, module, function, arity, trigger, call_meta, issues) do
    case forbidden_entry(context, module, function, arity) do
      {:ok, {message, display}} ->
        [issue_for(context, call_meta, trigger, display, function, message) | issues]

      :error ->
        issues
    end
  end

  defp forbidden_entry(context, module, function, arity) do
    if excepted?(context, module, function, arity) do
      :error
    else
      case entry_for(context.calls, module, function, arity) do
        {:ok, entry} -> {:ok, resolve_display(entry, module)}
        :error -> :error
      end
    end
  end

  defp excepted?(context, module, function, arity) do
    entry_for(context.except, module, function, arity) != :error
  end

  defp entry_for(entries, module, function, arity) do
    with :error <- function_entry(entries, module, function, arity),
         :error <- Map.fetch(entries.modules, module) do
      matching_entry(entries.module_patterns, module)
    end
  end

  # An entry naming a function is looked up on its own, since a bare call under
  # an unrestricted `import` is only ever read against one of those.
  defp function_entry(entries, module, function, arity) do
    with :error <- Map.fetch(entries.functions, {module, function, arity}),
         :error <- Map.fetch(entries.functions, {module, function, :any}) do
      matching_entry(entries.function_patterns, module, function, arity)
    end
  end

  defp matching_entry(patterns, module) do
    patterns
    |> Enum.find(fn {regex, _entry} -> Regex.match?(regex, module) end)
    |> found_entry()
  end

  defp matching_entry(patterns, module, function, arity) do
    patterns
    |> Enum.find(&matches_function?(&1, module, function, arity))
    |> found_entry()
  end

  defp matches_function?({regex, name, entry_arity, _entry}, module, function, arity) do
    name == function and entry_arity in [:any, arity] and Regex.match?(regex, module)
  end

  defp found_entry(nil), do: :error
  defp found_entry({_regex, entry}), do: {:ok, entry}
  defp found_entry({_regex, _function, _arity, entry}), do: {:ok, entry}

  # A pattern entry says nothing about which module a call names, so the module
  # the call resolved to is what the message names.
  defp resolve_display({message, :matched}, module), do: {message, ModulePattern.display(module)}
  defp resolve_display(entry, _module), do: entry

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
    calls |> Enum.map(&normalize_call/1) |> group_entries()
  end

  defp prepare_except(except) do
    except |> Enum.map(&normalize_except/1) |> group_entries()
  end

  defp group_entries(entries) do
    %{
      functions:
        Map.new(
          for {{:function, module, function, arity}, entry} <- entries,
              do: {{module, function, arity}, entry}
        ),
      modules: Map.new(for {{:module, module}, entry} <- entries, do: {module, entry}),
      function_patterns:
        for({{:function_pattern, regex, function, arity}, entry} <- entries, do: {regex, function, arity, entry}),
      module_patterns: for({{:module_pattern, regex}, entry} <- entries, do: {regex, entry})
    }
  end

  defp normalize_except({module, function, arity})
       when (is_atom(module) or is_binary(module)) and is_atom(function) and is_integer(arity) do
    {function_key(module, function, arity), nil}
  end

  defp normalize_except({module, function})
       when (is_atom(module) or is_binary(module)) and is_atom(function) do
    {function_key(module, function, :any), nil}
  end

  defp normalize_except(module) when is_atom(module) or is_binary(module) do
    {module_key(module), nil}
  end

  defp normalize_except(entry) do
    raise ArgumentError,
          "invalid except entry #{inspect(entry)}: expected Module, a module name pattern, " <>
            "{Module, :function}, or {Module, :function, arity}, without a message, since an " <>
            "exception reports nothing"
  end

  defp normalize_call({{module, function, arity}, message})
       when (is_atom(module) or is_binary(module)) and is_atom(function) and is_integer(arity) and
              is_binary(message) do
    {function_key(module, function, arity), entry(module, message)}
  end

  defp normalize_call({{module, function}, message})
       when (is_atom(module) or is_binary(module)) and is_atom(function) and is_binary(message) do
    {function_key(module, function, :any), entry(module, message)}
  end

  defp normalize_call({module, function, arity})
       when (is_atom(module) or is_binary(module)) and is_atom(function) and is_integer(arity) do
    {function_key(module, function, arity), entry(module, nil)}
  end

  defp normalize_call({module, function})
       when (is_atom(module) or is_binary(module)) and is_atom(function) do
    {function_key(module, function, :any), entry(module, nil)}
  end

  defp normalize_call({module, message})
       when (is_atom(module) or is_binary(module)) and is_binary(message) do
    {forbidden_module_key(module), entry(module, message)}
  end

  defp normalize_call(module) when is_atom(module) or is_binary(module) do
    {forbidden_module_key(module), entry(module, nil)}
  end

  defp normalize_call(entry) do
    raise ArgumentError,
          "invalid calls entry #{inspect(entry)}: expected Module, a module name pattern, " <>
            "{Module, :function}, {Module, :function, arity}, or any of those paired with a message"
  end

  defp function_key(module, function, arity) when is_atom(module) do
    {:function, module_name(module), function, arity}
  end

  defp function_key(pattern, function, arity) do
    {:function_pattern, ModulePattern.compile!(pattern), function, arity}
  end

  defp module_key(module) when is_atom(module), do: {:module, module_name(module)}
  defp module_key(pattern), do: {:module_pattern, ModulePattern.compile!(pattern)}

  # An exception reports nothing, so only a rule that would report every call in
  # the file is refused.
  defp forbidden_module_key(module) do
    key = module_key(module)

    forbid_kernel!(names_kernel?(key), module)

    key
  end

  defp names_kernel?({:module, name}), do: name == @kernel_module
  defp names_kernel?({:module_pattern, regex}), do: Regex.match?(regex, @kernel_module)

  defp forbid_kernel!(false, _named), do: :ok

  defp forbid_kernel!(true, named) do
    raise ArgumentError,
          "invalid calls entry #{inspect(named)}: `Kernel` cannot be forbidden as a whole " <>
            "module, since it is auto imported into every module, so name its functions instead"
  end

  defp entry(module, message) when is_atom(module), do: {message, module_display(module)}
  defp entry(_pattern, message), do: {message, :matched}

  defp module_name(module), do: ModuleName.full(module)

  defp module_display(module) do
    case Atom.to_string(module) do
      "Elixir." <> _ -> ModuleName.full(module)
      _ -> inspect(module)
    end
  end
end
