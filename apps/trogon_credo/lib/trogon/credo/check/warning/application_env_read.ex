defmodule Trogon.Credo.Check.Warning.ApplicationEnvRead do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      calls: [
        {Application, :get_env},
        {Application, :fetch_env},
        {Application, :fetch_env!},
        {Application, :get_all_env},
        {:application, :get_env},
        {:application, :get_all_env}
      ],
      module_references: true,
      hint: nil,
      allowed_files: []
    ],
    explanations: [
      check: """
      `Application.get_env/2,3` reads the application controller's global, node-wide
      table, so a function that calls it depends on state every test shares. A test that
      needs another value has to write that table with `Application.put_env/3`, which
      changes what every other test running at the same time reads, and cannot run
      `async: true`.

      A project that cannot pass its config in as an argument reads it through a facade
      it compiles per environment: `Application` in every environment but test, and a mock
      a test can stub per process in test, so one test overrides one key without writing
      to the table. `trogon_test` ships that mock, `Trogon.Test.MockApplication`, so the
      project writes only the facade:

          # preferred
          defmodule Acme do
            @application Application.compile_env(:acme, [__MODULE__, :application], Application)

            defdelegate get_env(app, key, default \\\\ nil), to: @application
          end

          defmodule Acme.Billing do
            def tax_rate do
              Acme.get_env(:acme, :tax_rate, 0.0)
            end
          end

          # NOT preferred
          defmodule Acme.Billing do
            def tax_rate do
              Application.get_env(:acme, :tax_rate, 0.0)
            end
          end

      Nothing reports a read that goes around the facade, which is what this check is
      for. `Trogon.Credo.Check.ExUnit.ApplicationEnvMutation` reports the writes a test
      makes when it has no facade to stub, and this check reports the reads in the code
      that should have used one, so the two together keep application env behind a seam.
      `Trogon.Credo.Check.Warning.SystemEnvRead` covers the operating system's
      environment instead.

      This check runs `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` with a default
      list covering `Application.get_env/2,3`, `Application.fetch_env/2`,
      `Application.fetch_env!/2`, `Application.get_all_env/0,1`, and the Erlang
      `:application.get_env/1,2,3` and `:application.get_all_env/0,1`, the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reports every call to them:
      qualified, through an alias, piped, captured, or written against the Erlang module
      directly. A bare call or capture is reported where an `import` brings the function
      in, `import Application, only: [get_env: 2]` for instance, and a read in the options
      of a `use` is reported too, since those options are evaluated when the module
      compiles.

      Reading the config at compile time is the recommended pattern, so
      `Application.compile_env/2,3` and `Application.compile_env!/2` are never reported,
      nor is anything written in their arguments. That is where the facade names its
      default, `Application.compile_env(:acme, [__MODULE__, :application], Application)`.
      Writing the environment, `Application.put_env/3,4`, and everything else on
      `Application` that is not a read of the environment, `ensure_all_started/1,2`,
      `spec/1,2`, `app_dir/1,2` and the like, is not reported either.

      There is a second way around the facade that a check on calls cannot see: handing
      the `Application` module around as a value and calling through the variable.

          {application, opts} = Keyword.pop(opts, :application, Application)
          application.get_env(app, key, [])

      The call has no module in it, so the only thing to report is the module reference
      itself, which is what `module_references` does. A bare `Application` is reported
      wherever it is written as a value: the default of a `Keyword.pop`, the right side
      of a match, the `to:` of a `defdelegate`. It is not reported as the target of a
      call, which is reported once as a call, in the arguments of `compile_env`, in an
      `alias`, `import`, `require`, or `use` directive, `use Application` in the
      application module being the usual one, in a typespec, in `@behaviour` or `@impl`,
      or as the name of a module being defined. A module such as `MyApp.Application`
      is another module and is never reported. A reference is resolved through the
      file's aliases and an explicit `Elixir.` prefix the way a call is. A reference
      written inside a `quote` block is read like any other code, the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reads a call there.

      A file is left alone when its path ends in the path of one of `allowed_files`,
      none by default. The facade itself normally needs no entry, since
      `defdelegate get_env(app, key, default), to: @application` is neither a call nor a
      reference to `Application`. Every entry is a `{path, reason}` tuple, and the reason
      is required: it states why that file may read application env directly, so whoever
      reads the `.credo.exs` learns the situation instead of guessing, and a bare path,
      a blank reason, or any other shape raises `ArgumentError`. The path is matched on
      whole segments, so `apps/acme/lib/acme/config.ex` and an absolute path to it are
      allowed by `lib/acme/config.ex`, and `myconfig.ex` is not allowed by `config.ex`.

      The check is not part of `Trogon.Credo.Plugin.Default`, since it only makes sense
      for a project that has a facade to point to, and that is a decision of the project.

          # .credo.exs
          {Trogon.Credo.Check.Warning.ApplicationEnvRead,
           hint: "Read it through Acme.get_env/3 instead.",
           allowed_files: [
             {"lib/acme/legacy_config.ex", "Moves behind Acme.get_env/3 with the legacy importer."}
           ]}
      """,
      params: [
        calls: """
        The calls this check forbids outside of `allowed_files`, given in the form
        `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` accepts for its own `calls:`
        param, without messages. Defaults to a list covering `Application.get_env`,
        `Application.fetch_env`, `Application.fetch_env!`, `Application.get_all_env`,
        `:application.get_env`, and `:application.get_all_env`. A project with its own
        way to read application env replaces the default with its own list.
        """,
        module_references: """
        Whether a bare reference to the `Application` module used as a value is reported,
        `Keyword.pop(opts, :application, Application)` for instance. Such a reference is
        the default of a call through a variable, which no check on calls can see.
        Defaults to `true`. Set it to `false` to report calls only.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can name its own facade, `"Read it through Acme.get_env/3 instead."` for
        instance. Skipped when set to `nil`, the default.
        """,
        allowed_files: """
        The files allowed to read application env directly, given as `{path, reason}`
        tuples. The path is matched against the end of a file's path on whole segments,
        and the reason is a non-blank string that documents why the file may read it; an
        entry without one raises `ArgumentError`. Defaults to no file, since the facade
        itself is not a call to `Application` nor a reference to it.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate
  alias Trogon.Credo.ModuleName

  @call_message "Application env read directly bypasses the project's facade, so a test " <>
                  "cannot mock it and has to mutate the global application env. Read it " <>
                  "through the facade instead."

  @reference_message "The `Application` module used as a value is the target of a dynamic call " <>
                       "that bypasses the project's facade, so a test cannot mock it and has " <>
                       "to mutate the global application env. Read application env through " <>
                       "the facade instead."

  @application "Application"
  @compile_time_reads [:compile_env, :compile_env!]
  @quiet_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep, :behaviour, :impl]
  @directives [:alias, :import, :require]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    allowed_files =
      params |> Params.get(:allowed_files, __MODULE__) |> List.wrap() |> Enum.map(&allowed_path!/1)

    if allowed_file?(source_file.filename, allowed_files) do
      []
    else
      call_issues(source_file, params) ++ reference_issues(source_file, params)
    end
  end

  defp call_issues(source_file, params) do
    calls = params |> Params.get(:calls, __MODULE__) |> List.wrap()

    CheckDelegate.run(source_file, params, __MODULE__, ForbiddenFunctionCall,
      calls: Enum.map(calls, &forbidden_call/1),
      except: [],
      hint: Params.get(params, :hint, __MODULE__),
      use_options: true
    )
  end

  defp reference_issues(source_file, params) do
    if Params.get(params, :module_references, __MODULE__) do
      context = %{
        issue_meta: IssueMeta.for(source_file, params),
        aliases: ModuleName.collect_aliases(source_file),
        hint: Params.get(params, :hint, __MODULE__)
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
    else
      []
    end
  end

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _context) when attribute in @quiet_attributes do
    {[], issues}
  end

  # The module a `use` names is not a reference to read, but its options are code.
  defp traverse({:use, _meta, [_module | options]}, issues, _context), do: {options, issues}

  defp traverse({directive, _meta, args}, issues, _context) when directive in @directives and is_list(args) do
    {[], issues}
  end

  defp traverse({:defmodule, _meta, [_name | rest]}, issues, _context), do: {rest, issues}

  # Reading config at compile time is the sanctioned pattern, and it is where a
  # facade names its default, so nothing in it is reported.
  defp traverse({{:., _, [{:__aliases__, _, parts}, function]}, _, args}, issues, context)
       when function in @compile_time_reads and is_list(args) do
    if application?(parts, context), do: {[], issues}, else: {args, issues}
  end

  # The module a call is made on is reported by the rule on calls, so only the
  # arguments are left to walk.
  defp traverse({{:., _, [{:__aliases__, _, _parts}, function]}, _, args}, issues, _context)
       when is_atom(function) and is_list(args) do
    {args, issues}
  end

  defp traverse({:__aliases__, meta, parts}, issues, context) do
    if application?(parts, context) do
      {[], [reference_issue(context, parts, meta) | issues]}
    else
      {[], issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp application?(parts, context), do: ModuleName.resolve(parts, context.aliases) == @application

  defp reference_issue(context, parts, meta) do
    format_issue(
      context.issue_meta,
      message: append_hint(@reference_message, context.hint),
      trigger: Name.full(parts),
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"

  defp allowed_path!({path, reason} = entry) when is_binary(path) and is_binary(reason) do
    if String.trim(reason) == "", do: invalid_allowed_file!(entry), else: path
  end

  defp allowed_path!(entry), do: invalid_allowed_file!(entry)

  defp invalid_allowed_file!(entry) do
    raise ArgumentError,
          "invalid allowed_files entry #{inspect(entry)}: expected a {path, reason} tuple " <>
            "with a non-blank reason string, such as " <>
            ~s({"test/support/postgres.ex", "Gates the Postgres tests on a database URL."})
  end

  # An allowed path matches the whole filename or a tail of it that starts at a
  # segment boundary, so `myconfig.ex` never counts as `config.ex`.
  defp allowed_file?(filename, allowed_files) do
    segments = Path.split(filename)

    Enum.any?(allowed_files, fn allowed ->
      allowed_segments = Path.split(allowed)
      Enum.take(segments, -length(allowed_segments)) == allowed_segments
    end)
  end

  defp forbidden_call({module, function, arity}) when is_atom(function) and is_integer(arity) do
    {{module, function, arity}, @call_message}
  end

  defp forbidden_call({module, function}) when is_atom(function), do: {{module, function}, @call_message}
  defp forbidden_call(module), do: {module, @call_message}
end
