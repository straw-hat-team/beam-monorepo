defmodule Trogon.Credo.Check.Commanded.ErrorOwnership do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      errors: ["(*.*).**Error"],
      constructors: [:exception, :new],
      shared: [],
      hint: nil
    ],
    explanations: [
      check: """
      An error belongs to the context that defines it, and that context is the one that
      decides when it happens. A context is whatever owns the decision, a domain layer,
      a command layer, or a web server that is its own domain; nothing here asks for a
      layer by name. Another context building that error decides something on the
      owner's behalf, and keeps deciding it the old way after the owner changes its
      rule. Reacting to the error, matching the `{:error, error}` the owner returns, or
      asking what it is with `is_exception/2`, leaves the decision with its owner and is
      never reported.

          # preferred
          defmodule Acme.Billing.Invoice do
            def register(%__MODULE__{status: :registered}, _command) do
              {:error, %Acme.Billing.AlreadyRegisteredError{}}
            end
          end

          defmodule Acme.Web.InvoiceController do
            def create(conn, params) do
              case Acme.Billing.register_invoice(params) do
                {:ok, invoice} -> send_created(conn, invoice)
                {:error, %Acme.Billing.AlreadyRegisteredError{} = error} -> send_conflict(conn, error)
              end
            end

            def show(conn, %{"id" => id}) do
              {:error, %Acme.Web.NotFoundError{id: id}}
            end
          end

          # NOT preferred
          defmodule Acme.Web.InvoiceController do
            def create(conn, params) do
              if already_registered?(params) do
                {:error, %Acme.Billing.AlreadyRegisteredError{}}
              end
            end
          end

      A test exercises another context only by stubbing it, and the error that context
      returns is exactly what the stub must produce, so a test file builds the owner's
      error on the owner's behalf out of necessity rather than neglect. There is no way
      to make `Mox.expect(..., fn -> {:error, Acme.Billing.AlreadyRegisteredError.new(id)} end)`
      match on an error it has not built. A file whose name ends in `_test.exs`, or that
      sits under a `test/support` directory anywhere in its path, stands in for the
      owner it stubs and is never reported.

      A context can also exist for every other context to build its errors against, a
      shared kernel rather than a context with secrets of its own. Listing it in
      `shared` opts it out of ownership entirely: once `"Acme.Platform"` is in `shared`,
      building `Acme.Platform.NotFoundError` from a gRPC handler or a web controller is
      never reported, no matter which context builds it.

      What counts as construction: a struct literal or a struct update, `%Error{}` and
      `%Error{e | ...}` alike, written where it is built rather than matched; `raise` and
      `reraise` naming the error module, `Kernel.`-qualified included; a call to one of
      its constructor functions, `exception` and `new` by default, called directly,
      piped into, or captured; and `struct/2` or `struct!/2` given the error module,
      `Kernel.`-qualified included. Everything else that names the module, a type check
      such as `is_exception/2`, any other function called on it, the module passed
      around as a plain value, an `alias`, a typespec, and a pattern anywhere a pattern
      may be written, a function head, a `case` or `with` clause, a `rescue` clause, a
      guard, is left alone, since none of those build the error.
      """,
      params: [
        errors: """
        A list of patterns whose parenthesized prefix names the owning context and whose
        remainder names its errors. Defaults to `["(*.*).**Error"]`, so the first two
        segments of an error module own it, `Acme.Billing` for
        `Acme.Billing.Domain.NotFoundError`. A project whose contexts sit deeper writes
        its own prefix, `"(Acme.*.*).**Error"` for instance. `*` matches within a single
        segment and `**` matches across segments, the same grammar
        `Trogon.Credo.Check.Design.NamespaceBoundary` documents for `private_to`.
        """,
        constructors: """
        A list of function names that build the error when called on it, a qualified
        call, a pipe, or a capture alike. Defaults to `[:exception, :new]`, which covers
        the function `defexception` generates and the constructor most error modules add
        beside it. A project naming its constructor differently replaces the default
        rather than adding to it, `constructors: [:build]` for instance.
        """,
        shared: """
        A list of owner patterns, written with the same grammar as the parenthesized
        prefix in `errors`, an exact module name or `*`/`**` wildcard segments alike.
        Building an error whose owner matches one of these patterns is never reported,
        regardless of which context builds it. Defaults to `[]`, so no context's errors
        are shared by default. A context every other context is meant to build errors
        for writes `shared: ["Acme.Platform"]`, for instance.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  alias Credo.Code.Name
  alias Trogon.Credo.AstPattern
  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.ModuleName
  alias Trogon.Credo.ModulePattern

  @message "Only the context that defines this error builds it; match on the error it " <>
             "returns instead of building it here."

  @kernel_constructions [:raise, :reraise, :struct, :struct!]

  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    if test_file?(source_file.filename) do
      []
    else
      run_on_context(source_file, params)
    end
  end

  defp run_on_context(source_file, params) do
    errors = params |> Params.get(:errors, __MODULE__) |> List.wrap()
    constructors = params |> Params.get(:constructors, __MODULE__) |> List.wrap()
    shared = params |> Params.get(:shared, __MODULE__) |> List.wrap()

    context = %{
      issue_meta: IssueMeta.for(source_file, params),
      owners: Enum.map(errors, &compile_owner!/1),
      own_module: ModuleDeclaration.outermost_module_name(source_file),
      constructors: MapSet.new(constructors),
      shared: Enum.map(shared, &compile_shared!/1),
      hint: Params.get(params, :hint, __MODULE__),
      aliases: ModuleName.collect_aliases(source_file)
    }

    Credo.Code.prewalk(source_file, &traverse(&1, &2, context), [])
  end

  # A test file stands in for the owner it stubs, since there is no way to make a
  # test double match on an error the owner has not yet returned, and a file
  # under `test/support` exists to build fixtures for the same reason.
  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs") or test_support_file?(filename)
  end

  defp test_support_file?(filename) do
    filename |> Path.split() |> under_test_support?()
  end

  defp under_test_support?(["test", "support" | _rest]), do: true
  defp under_test_support?([_segment | rest]), do: under_test_support?(rest)
  defp under_test_support?([]), do: false

  defp compile_owner!(pattern) do
    case ModulePattern.compile_owner_pattern(pattern) do
      {:ok, regex} -> regex
      :error -> raise ArgumentError, invalid_errors_pattern(pattern)
    end
  end

  defp invalid_errors_pattern(pattern) do
    "invalid errors pattern #{inspect(pattern)}: expected a string of the form " <>
      "\"(owner)\" or \"(owner).private\", where the parenthesized prefix names the owning namespace"
  end

  defp compile_shared!(pattern) do
    case ModulePattern.compile(pattern) do
      {:ok, regex} -> regex
      :error -> raise ArgumentError, invalid_shared_pattern(pattern)
    end
  end

  defp invalid_shared_pattern(pattern) do
    "invalid shared pattern #{inspect(pattern)}: expected a module name pattern as a string, " <>
      "or a plain module name"
  end

  defp traverse({:quote, _meta, _args}, issues, _context), do: {[], issues}

  defp traverse({:@, _meta, [{attribute, _, _}]}, issues, _context)
       when attribute in @typespec_attributes do
    {[], issues}
  end

  # `match?/2` compares a value against a pattern, so its first argument is a
  # pattern position even though the call itself is written as an expression,
  # `Kernel.`-qualified or not.
  defp traverse({:match?, _meta, [_pattern, value]}, issues, _context), do: {[value], issues}

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _kernel_meta, [:Kernel]}, :match?]}, _call_meta, [_pattern, value]},
         issues,
         _context
       ) do
    {[value], issues}
  end

  # A struct literal and a struct update share this shape, the fields telling
  # them apart mattering to neither, since both build the struct they name.
  defp traverse({:%, _meta, [{:__aliases__, alias_meta, parts}, {:%{}, _map_meta, _fields}]} = ast, issues, context) do
    {ast, maybe_report(parts, alias_meta, context, issues)}
  end

  defp traverse({kind, _meta, [{:__aliases__, alias_meta, parts} | _rest]} = ast, issues, context)
       when kind in @kernel_constructions do
    {ast, maybe_report(parts, alias_meta, context, issues)}
  end

  # `Kernel.`-qualified forms are tried ahead of a qualified constructor call,
  # which would otherwise claim this same shape and never find the error
  # module, since it is argument here rather than receiver.
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _kernel_meta, [:Kernel]}, kind]}, _call_meta,
          [{:__aliases__, alias_meta, parts} | _rest]} = ast,
         issues,
         context
       )
       when kind in @kernel_constructions do
    {ast, maybe_report(parts, alias_meta, context, issues)}
  end

  # A call reaches here whether written directly, piped into, or captured,
  # since each of those wraps the same qualified call shape and a prewalk
  # visits it either way.
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, alias_meta, parts}, function]}, _call_meta, args} = ast,
         issues,
         context
       )
       when is_atom(function) and is_list(args) do
    if MapSet.member?(context.constructors, function) do
      {ast, maybe_report(parts, alias_meta, context, issues)}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context) do
    case AstPattern.hide_pattern_position(ast) do
      {:ok, rewritten} -> {revisit(ast, rewritten), issues}
      :error -> {ast, issues}
    end
  end

  # A prewalk only walks into what a callback returns, never back over it, so a
  # rewritten expression is wrapped to be visited itself, unless it keeps the
  # form it was rewritten from, which would rewrite it again forever.
  defp revisit({form, _meta, _args}, {form, _rewritten_meta, _rewritten_args} = rewritten), do: rewritten
  defp revisit(_ast, rewritten), do: [rewritten]

  defp maybe_report(parts, meta, context, issues) do
    module = ModuleName.resolve(parts, context.aliases)

    report_if_foreign(module, Name.full(parts), meta, context, issues)
  end

  defp report_if_foreign(nil, _trigger, _meta, _context, issues), do: issues

  defp report_if_foreign(module, trigger, meta, context, issues) do
    case owner_of(module, context.owners) do
      nil -> issues
      owner -> report_if_outside(owner, trigger, meta, context, issues)
    end
  end

  defp report_if_outside(owner, trigger, meta, context, issues) do
    cond do
      ModulePattern.owner_includes?(context.own_module, owner) -> issues
      shared_owner?(owner, context.shared) -> issues
      true -> [issue_for(context.issue_meta, meta, trigger, context.hint) | issues]
    end
  end

  defp owner_of(module, owners) do
    Enum.find_value(owners, &ModulePattern.find_owner(module, &1))
  end

  defp shared_owner?(owner, shared), do: Enum.any?(shared, &Regex.match?(&1, owner))

  defp issue_for(issue_meta, meta, trigger, hint) do
    format_issue(
      issue_meta,
      message: append_hint(@message, hint),
      trigger: trigger,
      line_no: meta[:line],
      column: meta[:column]
    )
  end

  defp append_hint(message, nil), do: message
  defp append_hint(message, hint), do: "#{message} #{hint}"
end
