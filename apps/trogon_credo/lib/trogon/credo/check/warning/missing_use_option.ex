defmodule Trogon.Credo.Check.Warning.MissingUseOption do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      for_use: nil,
      options: [],
      hint: nil
    ],
    explanations: [
      check: """
      A `__using__/1` macro usually accepts options, and usually gives them
      defaults. That is convenient and occasionally dangerous: when the
      default silently decides something that outlives the code, omitting the
      option is a bug that nothing reports. An error template whose severity
      defaults to the least useful value, a background worker whose retry
      count defaults to whatever the library picked, a module whose identity
      prefix ends up in persisted data all compile, run, and are wrong in a
      way that only shows up in production data.

      A project that has decided an option must always be stated wants that
      decided in one place. This check is that place: it reports a `use` of a
      named module that does not pass the options the project requires.

          {Trogon.Credo.Check.Warning.MissingUseOption,
           [for_use: MyApp.Worker, options: [:queue, :max_attempts]]}

      With the configuration above, `use MyApp.Worker` reports both options
      missing, and `use MyApp.Worker, queue: :default` reports only
      `:max_attempts` missing.

      This check is presence only. Whether the value passed for an option is
      the right one is deliberately out of scope: a value constraint would
      need a nested keyword path to be useful, and that is a different check.

      Credo does not ship anything that inspects the options passed to a
      `use`, so there is no core check this narrows.

      The options passed to a `use` are only inspected when they are written
      as a keyword list literal in the source. `use MyApp.Worker, @worker_opts`,
      `use MyApp.Worker, unquote(opts)`, and
      `use MyApp.Worker, Keyword.merge(@base, queue: :x)` all stay silent,
      since the check cannot read what they pass and reporting options that
      may well be there would be worse than saying nothing. A partial keyword
      list with a non literal tail, `use MyApp.Worker, [queue: :default | rest]`,
      is not a keyword list literal either, and is skipped the same way. This
      is the main blind spot of this check: its value is on the ordinary
      literal form that almost all `use` calls take.

      A `use` written inside a `quote` block is inspected, since the macro
      injects that `use` with those options into every module that expands
      it. `Trogon.Credo.Check.Warning.ForbiddenUse` documents the same
      decision for its own case.

      Aliases are resolved before matching, so a `use` written through an
      alias is reported under the name of the module it resolves to. Aliases
      are collected for the whole file rather than per lexical scope, except
      for an `alias` written inside a `quote` block, which takes effect
      wherever the macro expands and is therefore not collected.

      A name the file binds to more than one module, two sibling modules
      aliasing a different `Client` for instance, matches neither module, and
      does not fall back to matching the name as written either, since the
      file as a whole does not say which one a given reference means.

      A module written with an explicit `Elixir.` prefix, such as
      `Elixir.MyApp.Worker`, names the same module as `MyApp.Worker` and is
      matched the same way.
      """,
      params: [
        for_use: """
        A module, or a list of modules, whose `use` this check inspects. Not
        configured, the default `nil`, makes the check inert, since there is
        no universal option that every `use` must pass.
        """,
        options: """
        A list of atom keys that every `use` of a `for_use` module must pass.
        Defaults to `[]`, which makes the check inert even when `for_use` is
        configured.
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

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    for_use = normalize_for_use(Params.get(params, :for_use, __MODULE__))
    options = normalize_options(Params.get(params, :options, __MODULE__))

    if for_use == [] or options == [] do
      []
    else
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        for_use: for_use,
        options: options,
        hint: Params.get(params, :hint, __MODULE__),
        aliases: ModuleName.collect_aliases(source_file)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context))
    end
  end

  defp traverse({:use, _meta, [{:__aliases__, meta, parts} | rest]} = ast, issues, context) do
    module = ModuleName.resolve(parts, context.aliases)

    if module in context.for_use do
      {ast, report_missing(rest, meta, Name.full(parts), module, issues, context)}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp report_missing(rest, meta, trigger, module, issues, context) do
    case passed_keys(rest) do
      {:ok, keys} ->
        context.options
        |> Enum.filter(&(&1 not in keys))
        |> Enum.map(&issue_for(context.issue_meta, meta, trigger, module, &1, context.hint))
        |> Enum.concat(issues)

      :error ->
        issues
    end
  end

  defp passed_keys([]), do: {:ok, []}

  defp passed_keys([opts]) do
    if keyword_literal?(opts) do
      {:ok, Keyword.keys(opts)}
    else
      :error
    end
  end

  defp passed_keys(_rest), do: :error

  defp keyword_literal?(list) when is_list(list) do
    Enum.all?(list, fn
      {key, _value} when is_atom(key) -> true
      _entry -> false
    end) and not partial_tail?(list)
  end

  defp keyword_literal?(_other), do: false

  defp partial_tail?(list) do
    Enum.any?(list, fn
      {_key, {:|, _meta, [_left, _right]}} -> true
      _entry -> false
    end)
  end

  defp issue_for(issue_meta, meta, trigger, module, option, hint) do
    format_issue(
      issue_meta,
      message: append_hint("The `use #{module}` must set the `#{option}:` option.", hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp normalize_for_use(nil), do: []
  defp normalize_for_use(modules) when is_list(modules), do: Enum.map(modules, &validate_module!/1)
  defp normalize_for_use(module), do: [validate_module!(module)]

  defp validate_module!(module) when is_atom(module), do: ModuleName.full(module)

  defp validate_module!(other) do
    raise ArgumentError, "invalid for_use #{inspect(other)}: expected a module, got: #{inspect(other)}"
  end

  defp normalize_options(nil), do: []
  defp normalize_options(options) when is_list(options), do: Enum.map(options, &validate_option!/1)

  defp normalize_options(other) do
    raise ArgumentError, "invalid options #{inspect(other)}: expected a list of atoms, got: #{inspect(other)}"
  end

  defp validate_option!(option) when is_atom(option), do: option

  defp validate_option!(other) do
    raise ArgumentError, "invalid options #{inspect(other)}: expected an atom, got: #{inspect(other)}"
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
