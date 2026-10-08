defmodule Trogon.Credo.Check.Commanded.DeterministicCommand do
  alias Trogon.Credo.Check.Warning.ForbiddenFunctionCall
  alias Trogon.Credo.CheckDelegate
  alias Trogon.Credo.ModuleDeclaration
  alias Trogon.Credo.NonDeterministicCalls

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      aggregate_modules: [Trogon.Commanded.Aggregate],
      command_handler_modules: [Trogon.Commanded.CommandHandler],
      command_modules: [Trogon.Commanded.Command],
      event_modules: [Trogon.Commanded.Event],
      calls: NonDeterministicCalls.calls(),
      hint: nil
    ],
    explanations: [
      check: """
      A command is decided from the aggregate state and the command alone: given the
      same state and the same command, the aggregate must reach the same decision
      every time. An aggregate or a command handler that calls out for the current
      time, for randomness, or for a freshly generated id decides something the
      command itself did not carry, so the same command replayed later, or handled
      by a different node, can produce a different event. The same holds for the
      command and event modules themselves: a default, a constructor, or a helper on
      them that draws a value is a decision the command did not carry either.

      The value belongs on the command instead. A caller that needs `DateTime.utc_now/0`
      or a new id reads it before dispatching, puts it on the command, and the
      aggregate only ever reads it back.

          # preferred
          defmodule Acme.Billing.Command.RegisterInvoice do
            defstruct [:invoice_id, :issued_at]
          end

          def handle(%Acme.Billing.Domain.Invoice{} = invoice, %RegisterInvoice{} = command) do
            Acme.Billing.Domain.Invoice.register(invoice, command.invoice_id, command.issued_at)
          end

          # NOT preferred
          def handle(%Acme.Billing.Domain.Invoice{} = invoice, %RegisterInvoice{} = command) do
            Acme.Billing.Domain.Invoice.register(invoice, Ecto.UUID.generate(), DateTime.utc_now())
          end

      This check runs `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` with a default
      list of calls that draw time, randomness, or an id, over every file that
      `Trogon.Credo.ModuleDeclaration` reports as declaring a module that `use`s one of
      `aggregate_modules`, `command_handler_modules`, `command_modules`, or
      `event_modules`. Scoping is per file: a file that
      declares such a module is checked whole, so a private function the aggregate calls
      is covered even when it is defined further down the same file. A call reached
      through an alias, a pipe, a capture, or an import is reported the way
      `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` reports it, and a whole module
      entry such as `:rand` covers every function on it.
      """,
      params: [
        aggregate_modules: """
        A list of modules that mark a module as an aggregate when brought in with
        `use`. Defaults to `Trogon.Commanded.Aggregate` itself; a project that wraps it
        in a macro of its own lists that wrapper here instead.
        """,
        command_handler_modules: """
        A list of modules that mark a module as a command handler when brought in with
        `use`. Defaults to `Trogon.Commanded.CommandHandler`.
        """,
        command_modules: """
        A list of modules that mark a module as a command when brought in with
        `use`. Defaults to `Trogon.Commanded.Command`.
        """,
        event_modules: """
        A list of modules that mark a module as an event when brought in with
        `use`. Defaults to `Trogon.Commanded.Event`.
        """,
        calls: """
        The calls this check forbids inside an aggregate, a command handler, a
        command, or an event, given in the form `Trogon.Credo.Check.Warning.ForbiddenFunctionCall` accepts for its
        own `calls:` param, without messages. Defaults to a list covering wall clock
        time, randomness, and id generation, through the standard library, `:crypto`,
        `:rand`, `:random`, `Ecto.UUID`, `Uniq.UUID`, `UUID`, and `Nanoid`. A project
        with its own source of one of those replaces the default with its own list.
        """,
        hint: """
        A sentence appended to the message of every issue this check reports, so a
        project can say in its own words what to do instead. Skipped when set to
        `nil`, the default.
        """
      ]
    ]

  @message "Put the value on the command instead of drawing it here, since a command " <>
             "and the events it produces are decided from the aggregate state and the " <>
             "command alone."

  @doc false
  @impl true
  def run(%SourceFile{} = source_file, params) do
    markers = markers(params)

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

  defp markers(params) do
    aggregate_modules = params |> Params.get(:aggregate_modules, __MODULE__) |> List.wrap()
    command_handler_modules = params |> Params.get(:command_handler_modules, __MODULE__) |> List.wrap()

    command_modules = params |> Params.get(:command_modules, __MODULE__) |> List.wrap()
    event_modules = params |> Params.get(:event_modules, __MODULE__) |> List.wrap()

    aggregate_modules ++ command_handler_modules ++ command_modules ++ event_modules
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
