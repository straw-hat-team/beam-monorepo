defmodule Trogon.Credo.Check.Commanded.SwappableNonDeterminism do
  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate
  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.NonDeterministicCalls

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      processor_modules: [Commanded.Event.Handler],
      calls: NonDeterministicCalls.calls(),
      hint: nil
    ],
    explanations: [
      check: """
      A processor, an event handler that reacts to what already happened, may depend
      on wall clock time, randomness, or a generated id, unlike an aggregate or a
      command handler: nothing about replaying its work has to reach the
      same decision twice. A test still has to replace what it depends on, though, or it
      cannot assert on the value a processor read. Calling `DateTime.utc_now/0` or
      `Ecto.UUID.generate/0` straight from a processor leaves no seam for a test to
      replace, so the rule is not "never", it is "never by calling the source directly":
      the value is read through a component the project can swap, a clock or an id
      generator module, and the processor calls that instead.

          # preferred
          defmodule Acme.Billing.EventHandler.InvoiceReminder do
            use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

            def handle(%InvoiceOverdue{} = event, _metadata) do
              %SendReminder{invoice_id: event.invoice_id, sent_at: Acme.Clock.utc_now()}
            end
          end

          # NOT preferred
          defmodule Acme.Billing.EventHandler.InvoiceReminder do
            use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

            def handle(%InvoiceOverdue{} = event, _metadata) do
              %SendReminder{invoice_id: event.invoice_id, sent_at: DateTime.utc_now()}
            end
          end

      This check runs `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` with a default
      list of calls that draw time, randomness, or an id, over every file that
      `Trogon.Credo.ModuleDeclaration` reports as declaring a module that `use`s one of
      `processor_modules`. A project whose processors also include job workers lists
      those too, `Oban.Pro.Worker` for instance. The swappable component itself, the
      clock or id generator a test replaces, lives outside `processor_modules`, so it is
      never itself scoped by this check and is free to call the source it wraps.

      Scoping is per file: a file that declares such a module is checked whole, so a
      private function the processor calls is covered even when it is defined further
      down the same file. A call reached through an alias, a pipe, a capture, or an
      import is reported the way `Trogon.Credo.Check.Warning.ForbiddenFunctionCall`
      reports it, and a whole module entry such as `:rand` covers every function on it.
      """,
      params: [
        processor_modules: """
        A list of modules that mark a module as a processor when brought in with
        `use`. Defaults to `Commanded.Event.Handler`. A project whose processors also
        include job workers adds those here, `Oban.Pro.Worker` for instance.
        """,
        calls: """
        The calls this check forbids inside a processor, given in the form
        `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` accepts for its own
        `calls:` param, without messages. Defaults to a list covering wall clock
        time, randomness, and id generation, through the standard library, `:crypto`,
        `:rand`, `:random`, `Ecto.UUID`, `Uniq.UUID`, `UUID`, and `Nanoid`. A project
        with its own source of one of those replaces the default with its own list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can name its own swappable component, `"Use MyApp.Clock.utc_now/0."`
        for instance. Skipped when set to `nil`, the default.
        """
      ]
    ]

  @message "Call a component the project can swap instead of calling this directly, " <>
             "since a processor may depend on time, randomness, or ids only through a " <>
             "seam a test can replace."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    markers = params |> Params.get(:processor_modules, __MODULE__) |> List.wrap()

    if declares_marked_module?(source_file, markers) do
      calls = params |> Params.get(:calls, __MODULE__) |> List.wrap()

      CheckDelegate.run(source_file, params, __MODULE__, ForbiddenFunctionCall,
        calls: Enum.map(calls, &forbidden_call/1),
        except: [],
        hint: Params.get(params, :hint, __MODULE__)
      )
    else
      []
    end
  end

  defp declares_marked_module?(source_file, markers) do
    source_file |> ModuleDeclaration.collect_module_declarations(using: markers) != []
  end

  defp forbidden_call({module, function, arity}) when is_atom(function) and is_integer(arity) do
    {{module, function, arity}, @message}
  end

  defp forbidden_call({module, function}) when is_atom(function), do: {{module, function}, @message}
  defp forbidden_call(module), do: {module, @message}
end
