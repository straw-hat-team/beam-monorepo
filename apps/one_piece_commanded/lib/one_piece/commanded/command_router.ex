defmodule OnePiece.Commanded.CommandRouter do
  @moduledoc """
  Command routing macro to allow configuration of each command to its command handler.

  Please read more about `Commanded.Commands.Router`.
  """

  @doc """
  It calls `Commanded.Commands.Router.__using__/1` and imports extra macros.
  """
  defmacro __using__(opts) do
    quote do
      use Commanded.Commands.Router, unquote(opts)
      import OnePiece.Commanded.CommandRouter
    end
  end

  @doc """
  Configure the command to be dispatched to the same command module.

  ## Example

      defmodule Router do
        use OnePiece.Commanded.CommandRouter
        register_transaction_script OpenBankAccount,
          aggregate: BankAccount
      end

      defmodule Router do
        use OnePiece.Commanded.CommandRouter
        # the aggregate module is `OpenBankAccount.Aggregate`
        register_transaction_script OpenBankAccount
      end


  Similar to `Commanded.Commands.Router.dispatch/2` except that,

  1. It uses the command module as the command handler as well.
  2. It uses the command module's aggregate identifier configuration.
  3. When no lifespan module is provided, it uses `OnePiece.Commanded.Aggregate.StatelessLifespan`. as the lifespan
     module to avoid OOM errors. Reliability is more important than performance.
  4. When no aggregate module is provided, it uses the command module name suffixed concat with `Aggregate` as the
     aggregate module.
     As an example, if the command module is `OpenBankAccount`, then the aggregate module is
     `OpenBankAccount.Aggregate`.
  5. Drops some options to avoid conflicts with the command module configuration.

  ### About the Transaction Script naming

  The naming comes from [Transaction Script from Martin Fowler](https://martinfowler.com/eaaCatalog/transactionScript.html),
  although it is not exactly the same since the original name is about database transactions, the key part is the
  following sentence:

  > A Transaction Script organizes all this logic primarily as a single procedure.

  This is the idea behind the `register_transaction_script/2` macro is to have the strongest cohesion possible for a
  given Use Case (Command in this case).
  Discouraging patterns around a single Command Handler that handles multiple commands, that over time, can become a
  a [God Module](https://en.wikipedia.org/wiki/God_object),

  God Modules that becomes difficult to maintain and understand. Having to come up with weird names for functions, scroll
  pass hundreds of lines of code to find the right piece of code to change, or bike-shedding around locations of the
  code, to the point that some developers will annotate with comments to indicate Labels for IDEs to jump to the right
  place, ect.

  ### Why to have an Aggregate per Command?

  The needs for an given Aggregate is driven by the command handler that requires such "state", it is not the other way
  around. The same problems with the God Module can happen with the God Aggregate.

  In practices, most of the `apply/2` functions will be a simple functions, barely anything passed basic permutations.
  Since the Aggregate state needs is driven by the command handler, it makes sense to have a 1:1 relationship between
  the command and the aggregate.

  The only dependency between the command handlers are the events, not the "state" of the aggregate. The existence of
  a given event may be due to another command handler, that is OK, a set of Command Handlers acts upon the same
  facts/events, the past is immutable, the past is the same for everyone, not the state of the aggregate.
  That is one reason why when you are doing testing you speak in terms of "given previous events" and not
  "given previous state".

  Being said, be pragmatic.

  ### FAQ

  Q: Should I have a `command.ex` and `command/aggregate.ex` files?
  A: Yes, but it is discouraged, use the same `command.ex` file to put the
  command and the aggregate. As we said before, high cohesion of the code is
  the goal, not the number of files, the more files you have, the more entropy
  you have to deal with, and since the aggregate is driven by the command
  handler, you are most likely to modify the command and the aggregate at the
  same time, or in the best case, ignore the aggregate module.

  Here is an example file structure:

      defmodule BankAccount.OpenBankAccount.Aggregate do
        use OnePiece.Commanded.Aggregate, identifier: :uuid
        embedded_schema do
          # ...
        end
      end

      defmodule BankAccount.OpenBankAccount do
        use OnePiece.Commanded.CommandHandler
        use OnePiece.Commanded.Command,
          aggregate_identifier: :uuid,
          stream_prefix: "bank-account-"

        alias BankAccount.{
          BankAccountOpened,
          OpenBankAccount
        }

        embedded_schema do
        end

        def handle(%OpenBankAccount.Aggregate{} = aggregate, %OpenBankAccount{} = command) do
          # ...
        end
      end



  Q: Am I allowed to reuse the same aggregate for multiple commands?
  A: Yes, you can, but it is discouraged, since it can lead to the God Aggregate problem.

  Q: Am I allowed to reuse code between aggregates?
  A: Yes, you can, but it is discouraged, a simple copy+paste could safe you from a lot of headaches in the future. Be
  mindful of the [Rule of Three](https://en.wikipedia.org/wiki/Rule_of_three_(computer_programming)). Use the
  `MyApp.[Stream Name].[Stream Name]` module as a place to put common code between aggregates.
  """
  @spec register_transaction_script(
          command_module :: module(),
          opts :: [aggregate: module(), lifespan: module()]
        ) :: Macro.t()
  defmacro register_transaction_script(command_module, opts \\ []) do
    command_module = Macro.expand(command_module, __CALLER__)

    aggregate_module =
      opts
      |> Keyword.replace_lazy(:aggregate, &Macro.expand(&1, __CALLER__))
      |> Keyword.get(:aggregate, Module.concat([command_module, "Aggregate"]))

    Code.ensure_compiled!(command_module)
    Code.ensure_compiled!(aggregate_module)

    opts =
      opts
      |> Keyword.take([:before_execute, :timeout, :lifespan, :consistency])
      |> Keyword.put(:aggregate, aggregate_module)
      |> Keyword.put(:to, command_module)
      |> Keyword.put(:identity, Kernel.apply(command_module, :aggregate_identifier, []))
      |> Keyword.put(:identity_prefix, Kernel.apply(command_module, :stream_prefix, []))
      |> Keyword.put_new(:lifespan, OnePiece.Commanded.Aggregate.StatelessLifespan)

    quote do
      Commanded.Commands.Router.dispatch(unquote(command_module), unquote(opts))
    end
  end

  @doc """
  Identify a given aggregate.

  ## Example
      defmodule BankAccount do
        use OnePiece.Commanded.Aggregate
          identifier: :uuid,
          stream_prefix: "bank-account-"

        embedded_schema do
          # ...
        end
      end

      defmodule Router do
        use OnePiece.Commanded.CommandRouter
        identify_aggregate OpenBankAccount
      end
  """
  defmacro identify_aggregate(aggregate_module) do
    aggregate_module = Macro.expand(aggregate_module, __CALLER__)

    Code.ensure_compiled!(aggregate_module)

    opts = [
      by: Kernel.apply(aggregate_module, :identifier, []),
      prefix: Kernel.apply(aggregate_module, :stream_prefix, [])
    ]

    quote do
      Commanded.Commands.Router.identify(unquote(aggregate_module), unquote(opts))
    end
  end
end
