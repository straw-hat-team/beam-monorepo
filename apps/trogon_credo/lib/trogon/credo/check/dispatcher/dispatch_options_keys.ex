defmodule Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      dispatch_options_modules: [Trogon.Dispatcher.DispatchOptions],
      except_in: ["Trogon.Dispatcher", "Trogon.Dispatcher.**"],
      hint: nil
    ],
    explanations: [
      check: """
      `Trogon.Dispatcher.DispatchOptions.new/1` and `new!/1` check only one thing at runtime:
      that every key is one of `:message_id`, `:correlation_id`, `:causation_id`, `:actor` and
      `:assigns`, given at most once. Everything else `t:Trogon.Dispatcher.DispatchOptions.option/0`
      states is a type, not a runtime check: that the argument is itself a keyword list, that
      `assigns` is a map, that the map's keys are atoms, and that `message_id`, `correlation_id`
      and `causation_id` implement `String.Chars`, since OpenTelemetry calls `to_string/1` on
      whichever of them a caller sets, with no guard in front of it.

      A literal argument is the one place a wrong value is caught before it ever reaches
      runtime, so this check reports the ways a literal can break what `new/1` itself does not
      check: the argument not being a keyword list at all, a key outside the five above, the
      same key given more than once, `assigns` not being a map, a non-atom key inside a literal
      `assigns` map, and a tuple or a map literal given for `message_id`, `correlation_id` or
      `causation_id`.

          # preferred
          DispatchOptions.new!(actor: actor, assigns: %{tenant: tenant})

          # NOT preferred
          DispatchOptions.new!(%{actor: actor})
          DispatchOptions.new!(actor: actor, actor: other_actor)
          DispatchOptions.new!(assigns: [tenant: tenant])
          DispatchOptions.new!(assigns: %{"tenant" => tenant})
          DispatchOptions.new!(message_id: {:ref, ref})

      Reported: a call to `new/1` or `new!/1` on one of `dispatch_options_modules`, written
      piped or not, whose argument is a map literal or another non-list literal instead of a
      keyword list; a literal keyword list with a key outside the five above, or the same key
      written twice; a literal `assigns` value that is not a map, or a literal `assigns` map
      with a key that is not a literal atom; and a literal tuple or map given for `message_id`,
      `correlation_id` or `causation_id`.

      Not reported: anything dynamic, a variable, a function call, or a list whose elements are
      not all recognizably literal `key: value` pairs, since there is nothing to check without
      running it; a struct literal given for `message_id`, `correlation_id` or `causation_id`,
      since a struct can implement `String.Chars` even though a bare map or tuple never does;
      and anything under `except_in`.
      """,
      params: [
        dispatch_options_modules: """
        A list of modules whose `new/1` and `new!/1` are checked. Defaults to
        `Trogon.Dispatcher.DispatchOptions`.
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

  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @functions [:new, :new!]
  @keys [:message_id, :correlation_id, :causation_id, :actor, :assigns]
  @id_keys [:message_id, :correlation_id, :causation_id]

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
        markers: markers(params, :dispatch_options_modules),
        hint: Params.get(params, :hint, __MODULE__)
      }

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
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

  # `Mod.new(opts)` / `Mod.new!(opts)`, not piped.
  defp traverse(
         {{:., _dmeta, [{:__aliases__, _ameta, parts}, function]}, cmeta, [opts_ast]} = ast,
         issues,
         context
       )
       when function in @functions do
    {ast, check_call(parts, function, opts_ast, cmeta, context, issues)}
  end

  # `lhs |> Mod.new()` / `lhs |> Mod.new!()`, piped.
  defp traverse(
         {:|>, _pmeta, [lhs, {{:., _dmeta, [{:__aliases__, _ameta, parts}, function]}, cmeta, []}]} = ast,
         issues,
         context
       )
       when function in @functions do
    {ast, check_call(parts, function, lhs, cmeta, context, issues)}
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp check_call(parts, function, opts_ast, cmeta, context, issues) do
    if MapSet.member?(context.markers, ModuleName.resolve(parts, context.aliases)) do
      classify(opts_ast, Atom.to_string(function), cmeta, context, issues)
    else
      issues
    end
  end

  defp classify([], _trigger, _cmeta, _context, issues), do: issues

  defp classify(opts_ast, trigger, cmeta, context, issues) when is_list(opts_ast) do
    case literal_keyword_pairs(opts_ast) do
      {:ok, pairs} -> check_pairs(pairs, trigger, cmeta, context, issues)
      :error -> issues
    end
  end

  defp classify({:%{}, _meta, pairs}, trigger, cmeta, context, issues) when is_list(pairs) do
    [not_a_keyword_list_issue(context, trigger, cmeta) | issues]
  end

  defp classify(literal, trigger, cmeta, context, issues) when is_number(literal) or is_binary(literal) do
    [not_a_keyword_list_issue(context, trigger, cmeta) | issues]
  end

  defp classify(literal, trigger, cmeta, context, issues) when is_atom(literal) and literal != nil do
    [not_a_keyword_list_issue(context, trigger, cmeta) | issues]
  end

  defp classify(_dynamic_ast, _trigger, _cmeta, _context, issues), do: issues

  defp literal_keyword_pairs(list) do
    if Enum.all?(list, &literal_pair?/1) do
      {:ok, list}
    else
      :error
    end
  end

  defp literal_pair?({key, _value}), do: is_atom(key)
  defp literal_pair?(_other), do: false

  defp check_pairs(pairs, trigger, cmeta, context, issues) do
    issues
    |> add_unknown_key_issues(pairs, trigger, cmeta, context)
    |> add_duplicate_key_issues(pairs, trigger, cmeta, context)
    |> add_assigns_issues(pairs, trigger, cmeta, context)
    |> add_id_issues(pairs, trigger, cmeta, context)
  end

  defp add_unknown_key_issues(issues, pairs, trigger, cmeta, context) do
    pairs
    |> Keyword.keys()
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @keys))
    |> Enum.reduce(issues, fn key, acc -> [unknown_key_issue(context, trigger, cmeta, key) | acc] end)
  end

  defp add_duplicate_key_issues(issues, pairs, trigger, cmeta, context) do
    pairs
    |> Keyword.keys()
    |> Enum.filter(&(&1 in @keys))
    |> duplicated_keys()
    |> Enum.reduce(issues, fn key, acc -> [duplicate_key_issue(context, trigger, cmeta, key) | acc] end)
  end

  defp duplicated_keys(keys) do
    keys
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(fn {key, _count} -> key end)
  end

  defp add_assigns_issues(issues, pairs, trigger, cmeta, context) do
    case Keyword.fetch(pairs, :assigns) do
      {:ok, assigns_ast} -> assigns_issues(assigns_ast, trigger, cmeta, context, issues)
      :error -> issues
    end
  end

  defp assigns_issues({:%{}, _meta, assigns_pairs}, trigger, cmeta, context, issues) when is_list(assigns_pairs) do
    assigns_pairs
    |> Enum.reject(fn {key, _value} -> is_atom(key) end)
    |> Enum.reduce(issues, fn {key, _value}, acc -> [non_atom_assigns_key_issue(context, trigger, cmeta, key) | acc] end)
  end

  defp assigns_issues(literal, trigger, cmeta, context, issues)
       when is_number(literal) or is_binary(literal) or is_list(literal) do
    [assigns_not_a_map_issue(context, trigger, cmeta, literal) | issues]
  end

  defp assigns_issues(literal, trigger, cmeta, context, issues) when is_atom(literal) do
    [assigns_not_a_map_issue(context, trigger, cmeta, literal) | issues]
  end

  defp assigns_issues(_dynamic_ast, _trigger, _cmeta, _context, issues), do: issues

  defp add_id_issues(issues, pairs, trigger, cmeta, context) do
    Enum.reduce(@id_keys, issues, fn key, acc -> add_id_issue(acc, pairs, key, trigger, cmeta, context) end)
  end

  defp add_id_issue(issues, pairs, key, trigger, cmeta, context) do
    case Keyword.fetch(pairs, key) do
      {:ok, value_ast} -> id_issues(value_ast, key, trigger, cmeta, context, issues)
      :error -> issues
    end
  end

  defp id_issues({:{}, _meta, _elems}, key, trigger, cmeta, context, issues) do
    [not_stringable_issue(context, trigger, cmeta, key) | issues]
  end

  defp id_issues({_left, _right}, key, trigger, cmeta, context, issues) do
    [not_stringable_issue(context, trigger, cmeta, key) | issues]
  end

  defp id_issues({:%{}, _meta, pairs}, key, trigger, cmeta, context, issues) when is_list(pairs) do
    [not_stringable_issue(context, trigger, cmeta, key) | issues]
  end

  defp id_issues(_other_ast, _key, _trigger, _cmeta, _context, issues), do: issues

  defp not_a_keyword_list_issue(context, trigger, cmeta) do
    issue_for(
      context,
      trigger,
      cmeta,
      "The argument must be a keyword list, since every dispatch option is given as a `key: value` pair."
    )
  end

  defp unknown_key_issue(context, trigger, cmeta, key) do
    issue_for(
      context,
      trigger,
      cmeta,
      "#{inspect(key)} is not a known dispatch option; expected one of :message_id, :correlation_id, " <>
        ":causation_id, :actor, :assigns."
    )
  end

  defp duplicate_key_issue(context, trigger, cmeta, key) do
    issue_for(
      context,
      trigger,
      cmeta,
      "#{inspect(key)} is given more than once; give each dispatch option at most once."
    )
  end

  defp assigns_not_a_map_issue(context, trigger, cmeta, literal) do
    issue_for(context, trigger, cmeta, "`assigns` must be a map, got: #{inspect(literal)}.")
  end

  defp non_atom_assigns_key_issue(context, trigger, cmeta, key) do
    issue_for(context, trigger, cmeta, "assigns key #{inspect(key)} must be an atom.")
  end

  defp not_stringable_issue(context, trigger, cmeta, key) do
    issue_for(
      context,
      trigger,
      cmeta,
      "#{key} must implement `String.Chars`, since it is rendered with `to_string/1`; " <>
        "a tuple or a bare map never does."
    )
  end

  defp issue_for(context, trigger, meta, message) do
    format_issue(
      context.issue_meta,
      message: append_hint(message, context.hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
