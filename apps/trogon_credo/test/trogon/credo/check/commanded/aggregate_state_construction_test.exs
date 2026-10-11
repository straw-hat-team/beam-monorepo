defmodule Trogon.Credo.Check.Commanded.AggregateStateConstructionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.AggregateStateConstruction

  describe "calls from outside the aggregate" do
    test "does not report anything when no module uses an aggregate module" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        def apply(aggregate, _event), do: aggregate
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "reports a call through an alias" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.apply/2` directly, since that bypasses the command handler " <>
                   "and can build a state the handler could never produce."
      end)
    end

    test "reports a call through the fully qualified name" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(aggregate, event) do
          Acme.Review.Domain.Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Acme.Review.Domain.Aggregate"
      end)
    end

    test "reports a piped call" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          aggregate |> Aggregate.apply(event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a captured call" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def evolver, do: &Aggregate.apply/2
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a call written with an explicit Elixir prefix" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(aggregate, event) do
          Elixir.Acme.Review.Domain.Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Elixir.Acme.Review.Domain.Aggregate"
      end)
    end

    test "reports a call through an alias given with :as" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate, as: ReviewAggregate

        def run(aggregate, event) do
          ReviewAggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "ReviewAggregate"
      end)
    end

    test "reports Kernel.apply/3 dynamically dispatching to a collected aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          Kernel.apply(Aggregate, :apply, [aggregate, event])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.apply/2` directly, since that bypasses the command handler " <>
                   "and can build a state the handler could never produce."
      end)
    end

    test "reports a call from inside a dynamically named nested module" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defmodule __MODULE__.Child do
          def run(aggregate, event) do
            Aggregate.apply(aggregate, event)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report a call to apply on a module that is not a collected aggregate" do
      """
      defmodule Acme.Review.Helper do
        def apply(aggregate, _event), do: aggregate
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Helper

        def run(aggregate, event) do
          Helper.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "reports a call through a custom aggregate_modules entry" do
      """
      defmodule Acme.Aggregate do
        defmacro __using__(_opts), do: quote(do: :ok)
      end

      defmodule Acme.Review.Domain.Aggregate do
        use Acme.Aggregate
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction, aggregate_modules: [Acme.Aggregate])
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "appends the hint to the message" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, event) do
          Aggregate.apply(aggregate, event)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction, hint: "Use the command handler case in tests instead.")
      |> assert_issue(fn issue ->
        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.apply/2` directly, since that bypasses the command handler " <>
                   "and can build a state the handler could never produce. " <>
                   "Use the command handler case in tests instead."
      end)
    end

    test "reports a call in a different file than the one that defines the aggregate" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Test do
          alias Acme.Review.Domain.Aggregate

          def run(aggregate, event) do
            Aggregate.apply(aggregate, event)
          end
        end
        """
        |> to_source_file("test/acme/review_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.filename == "test/acme/review_test.exs"
        assert issue.trigger == "Aggregate"
      end)
    end
  end

  describe "calls from inside the aggregate" do
    test "reports a bare local call to apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{} = event) do
          apply(aggregate, %Submitted{from: event})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "apply"

        assert issue.message ==
                 "Extract the shared logic into a private function instead of calling `apply/2` " <>
                   "from another `apply/2` clause, since `apply/2` is the aggregate's single entry point " <>
                   "and is invoked only by the framework."
      end)
    end

    test "reports a call to __MODULE__.apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{} = event) do
          __MODULE__.apply(aggregate, %Submitted{from: event})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "__MODULE__.apply"
      end)
    end

    test "reports a captured &apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, _event), do: aggregate

        def evolver, do: &apply/2
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "apply"
      end)
    end

    test "reports a captured &__MODULE__.apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, _event), do: aggregate

        def evolver, do: &__MODULE__.apply/2
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "__MODULE__.apply"
      end)
    end

    test "reports a piped call to apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{} = event) do
          aggregate |> apply(%Submitted{from: event})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "apply"
      end)
    end

    test "reports apply(__MODULE__, :apply, args)" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{} = event) do
          apply(__MODULE__, :apply, [aggregate, %Submitted{from: event}])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "apply"
      end)
    end

    test "reports Kernel.apply(__MODULE__, :apply, args)" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{} = event) do
          Kernel.apply(__MODULE__, :apply, [aggregate, %Submitted{from: event}])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Kernel.apply"
      end)
    end

    test "does not report the def apply/2 clauses that define the callback" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{} = event) when event.from != nil do
          aggregate
        end

        def apply(%__MODULE__{} = aggregate, %Approved{}) do
          aggregate
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a call from a @spec typespec on the callback" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        @spec apply(t(), event) :: t()
        def apply(%__MODULE__{} = aggregate, _event), do: aggregate
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a call inside a non-typespec module attribute" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        @initial_state apply(%__MODULE__{}, %Submitted{})

        def apply(%__MODULE__{} = aggregate, _event), do: aggregate
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "apply"
      end)
    end

    test "does not report a defdelegate whose head is apply/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        defdelegate apply(aggregate, event), to: Acme.Review.Domain.Evolver
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a private helper shared by multiple apply clauses" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(%__MODULE__{} = aggregate, %Submitted{}) do
          transition(aggregate, :submitted)
        end

        def apply(%__MODULE__{} = aggregate, %Rejected{}) do
          transition(aggregate, :rejected)
        end

        defp transition(aggregate, status) do
          Map.put(aggregate, :status, status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a local apply/2 call in a module that is not a collected aggregate" do
      """
      defmodule Acme.Review.NotAnAggregate do
        def apply(a, e), do: run(a, e)

        defp run(a, _e), do: a
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a local apply/3 call in a module that is not a collected aggregate" do
      """
      defmodule Acme.Review.NotAnAggregate do
        def run(fun, args) do
          apply(fun, :call, args)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end
  end

  describe "the suggestion depends on where the call is" do
    @aggregate """
    defmodule Acme.Review.Domain.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
    end
    """

    test "suggests Commanded.Aggregate.Multi from a command handler" do
      [
        to_source_file(@aggregate, "lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Command.ApproveReview do
          use Trogon.Commanded.CommandHandler

          alias Acme.Review.Domain.Aggregate

          def handle(aggregate, command) do
            aggregate
            |> Aggregate.apply(%ReviewSubmitted{id: command.id})
            |> approve(command)
          end
        end
        """
        |> to_source_file("lib/acme/review/command/approve_review.ex")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Use `Commanded.Aggregate.Multi` instead of calling `Acme.Review.Domain.Aggregate.apply/2` " <>
                   "directly, since `Multi.execute/2` hands each step the aggregate with the previous step's " <>
                   "events already applied."
      end)
    end

    test "recognizes a command handler through an aliased use" do
      [
        to_source_file(@aggregate, "lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Command.ApproveReview do
          alias Trogon.Commanded.CommandHandler
          use CommandHandler

          def handle(aggregate, event), do: Acme.Review.Domain.Aggregate.apply(aggregate, event)
        end
        """
        |> to_source_file("lib/acme/review/command/approve_review.ex")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Use `Commanded.Aggregate.Multi`"
      end)
    end

    test "suggests Commanded.Aggregate.Multi from a custom command handler module" do
      [
        to_source_file(@aggregate, "lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Command.ApproveReview do
          use Acme.CommandHandler

          def handle(aggregate, event), do: Acme.Review.Domain.Aggregate.apply(aggregate, event)
        end
        """
        |> to_source_file("lib/acme/review/command/approve_review.ex")
      ]
      |> run_check(AggregateStateConstruction, command_handler_modules: [Acme.CommandHandler])
      |> assert_issue(fn issue ->
        assert issue.message =~ "Use `Commanded.Aggregate.Multi`"
      end)
    end

    test "suggests the command handler case from a test" do
      [
        to_source_file(@aggregate, "lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert Aggregate.apply(%Aggregate{}, %ReviewSubmitted{}).status == :submitted
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Test through the command handler with `Trogon.Commanded.TestSupport.CommandHandlerCase` " <>
                   "instead of calling `Acme.Review.Domain.Aggregate.apply/2` directly, since that builds a " <>
                   "state the command handler could never produce."
      end)
    end

    test "suggests a custom command handler case from a test" do
      [
        to_source_file(@aggregate, "lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          test "submits" do
            Acme.Review.Domain.Aggregate.apply(%{}, %ReviewSubmitted{})
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction, command_handler_case: Acme.CommandHandlerCase)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Test through the command handler with `Acme.CommandHandlerCase`"
      end)
    end

    test "suggests a shared private function when the aggregate names itself" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(aggregate, %Approved{} = event) do
          Acme.Review.Domain.Aggregate.apply(aggregate, %Submitted{from: event})
        end
      end
      """
      |> to_source_file("lib/acme/review/domain/aggregate.ex")
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Extract the shared logic into a private function"
      end)
    end
  end

  describe "constructor calls from outside the aggregate" do
    test "reports a call to new/1 through an alias" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Aggregate.new(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.new` directly, since that builds a state nothing in " <>
                   "production ever reaches."
      end)
    end

    test "reports a call to new!/1 through the fully qualified name" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(attrs) do
          Acme.Review.Domain.Aggregate.new!(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Acme.Review.Domain.Aggregate"
      end)
    end

    test "reports a piped call to new/1" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          attrs |> Aggregate.new()
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a captured call to new!/1" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def factory, do: &Aggregate.new!/1
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports apply(Mod, :new, args) dynamically dispatching to a collected aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          apply(Aggregate, :new, [attrs])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports Kernel.apply(Mod, :new!, args) dynamically dispatching to a collected aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Kernel.apply(Aggregate, :new!, [attrs])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report a call to a constructor function on a module that is not a collected aggregate" do
      """
      defmodule Acme.Review.Helper do
        def new(attrs), do: attrs
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Helper

        def run(attrs) do
          Helper.new(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a call to another public function of the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def submitted?(%__MODULE__{status: status}), do: status == :submitted
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate) do
          Aggregate.submitted?(aggregate)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "reports a call through a custom constructor_functions entry" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Aggregate.build(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction, constructor_functions: [:build])
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "suggests the command handler case from a test" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert Aggregate.new!(%{status: :submitted}).status == :submitted
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Test through the command handler with `Trogon.Commanded.TestSupport.CommandHandlerCase` " <>
                   "instead of calling `Acme.Review.Domain.Aggregate.new!` directly, since that builds a " <>
                   "state nothing in production ever reaches; use `assert_events/3` or `assert_error/3` with " <>
                   "the events that lead to the state you want to exercise."
      end)
    end

    test "does not recommend assert_state from a test" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert Aggregate.new!(%{status: :submitted}).status == :submitted
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        refute issue.message =~ "assert_state"
      end)
    end

    test "reports a construction call made from inside a command handler the same way as elsewhere" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Command.ApproveReview do
          use Trogon.Commanded.CommandHandler

          alias Acme.Review.Domain.Aggregate

          def handle(_aggregate, command) do
            Aggregate.new!(%{id: command.id})
          end
        end
        """
        |> to_source_file("lib/acme/review/command/approve_review.ex")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.new!` directly, since that builds a state nothing in " <>
                   "production ever reaches."
      end)
    end
  end

  describe "constructor calls from inside the aggregate" do
    test "does not report a bare local call to new/1" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def build_initial(attrs) do
          new(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a call to __MODULE__.new!/1" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def build_initial(attrs) do
          __MODULE__.new!(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a call through the aggregate's own full name" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def build_initial(attrs) do
          Acme.Review.Domain.Aggregate.new(attrs)
        end
      end
      """
      |> to_source_file("lib/acme/review/domain/aggregate.ex")
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a call to a different aggregate's constructor made from inside this one" do
      """
      defmodule Acme.Order.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        alias Acme.Order.Aggregate, as: OrderAggregate

        def build_initial(attrs) do
          OrderAggregate.new(attrs)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "OrderAggregate"
      end)
    end
  end

  describe "struct literals from outside the aggregate" do
    test "reports a struct literal built through an alias" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          %Aggregate{status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`%Acme.Review.Domain.Aggregate{...}` directly, since that builds a state nothing in " <>
                   "production ever reaches."
      end)
    end

    test "reports a struct literal written with the fully qualified name" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(attrs) do
          %Acme.Review.Domain.Aggregate{status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Acme.Review.Domain.Aggregate"
      end)
    end

    test "reports a struct literal written with an explicit Elixir prefix" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(attrs) do
          %Elixir.Acme.Review.Domain.Aggregate{status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Elixir.Acme.Review.Domain.Aggregate"
      end)
    end

    test "reports a struct literal inside a pipe" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          %Aggregate{status: attrs.status} |> Map.from_struct()
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a struct literal passed as an argument" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Map.from_struct(%Aggregate{status: attrs.status})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a struct literal bound to a variable" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          built = %Aggregate{status: attrs.status}
          built
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report the empty struct literal" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          %Aggregate{}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a struct literal on a module that is not a collected aggregate" do
      """
      defmodule Acme.Review.Helper do
        defstruct [:status]
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Helper

        def run(attrs) do
          %Helper{status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "reports the struct update form" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(aggregate, attrs) do
          %Aggregate{aggregate | status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`%Acme.Review.Domain.Aggregate{... | ...}` directly, since that builds a state nothing in " <>
                   "production ever reaches."
      end)
    end
  end

  describe "struct literals from inside the aggregate" do
    test "does not report the empty struct literal in an apply/2 clause" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(nil, %Submitted{} = event), do: %__MODULE__{id: event.id, status: :submitted}
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a struct literal built through __MODULE__" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def apply(aggregate, %Submitted{} = event), do: %__MODULE__{aggregate | status: :submitted}
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a struct literal built through the aggregate's own full name" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def build_initial(attrs) do
          %Acme.Review.Domain.Aggregate{status: attrs.status}
        end
      end
      """
      |> to_source_file("lib/acme/review/domain/aggregate.ex")
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a struct literal naming a different aggregate made from inside this one" do
      """
      defmodule Acme.Order.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        alias Acme.Order.Aggregate, as: OrderAggregate

        def build_initial(attrs) do
          %OrderAggregate{status: attrs.status}
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "OrderAggregate"
      end)
    end
  end

  describe "struct/2 and struct!/2 calls" do
    test "reports struct/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          struct(Aggregate, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`struct(Acme.Review.Domain.Aggregate, ...)` directly, since that builds a state nothing " <>
                   "in production ever reaches."
      end)
    end

    test "reports struct!/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          struct!(Aggregate, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports Kernel.struct/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Kernel.struct(Aggregate, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report struct/1 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          struct(Aggregate)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report struct/2 given an empty list of fields" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          struct(Aggregate, [])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report struct/2 given an empty map of fields" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          struct(Aggregate, %{})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report struct/2 naming the aggregate from inside it" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id

        def build_initial(attrs) do
          struct(__MODULE__, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end
  end

  describe "struct literals and pattern matching" do
    test "allows a struct literal in a function head" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(%Aggregate{status: status}), do: status
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a case clause" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(value) do
          case value do
            %Aggregate{status: status} -> status
            _other -> nil
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a with clause" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(value) do
          with %Aggregate{status: status} <- value do
            status
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal on the left side of =" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(value) do
          %Aggregate{status: status} = value
          status
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a struct literal on the right side of =" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          built = %Aggregate{status: attrs.status}
          built
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "allows a struct literal as the pattern of match?/2" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(value) do
          match?(%Aggregate{status: :submitted}, value)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal matched by assert" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert %Aggregate{status: :submitted} = aggregate_under_test()
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a defmacro head" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defmacro assert_approved(%Aggregate{status: :approved} = value) do
          quote do: unquote(value)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a defmacrop head" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defmacrop assert_approved(%Aggregate{status: :approved} = value) do
          quote do: unquote(value)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a defguard head" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defguard is_approved(%Aggregate{status: status}) when status == :approved
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a defguardp head" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defguardp is_approved(%Aggregate{status: status}) when status == :approved
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a struct literal used as a defmacro head's \\ default value, which is an expression" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defmacro build(value \\\\ %Aggregate{status: :approved}) do
          quote do: unquote(value)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "still leaves a struct literal quoted in a macro body alone, since a quote block's contents are not looked at" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defmacro build_approved do
          quote do
            %Aggregate{status: :approved}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal as the pattern of assert_receive/1" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert_receive(%Aggregate{status: :submitted})
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal as the pattern of assert_received/1" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            assert_received(%Aggregate{status: :submitted})
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal as the pattern of refute_receive/1, still reporting its timeout argument" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            refute_receive(%Aggregate{status: :submitted}, %Aggregate{status: :approved})
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "allows a struct literal as the pattern of refute_received/1" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits" do
            refute_received(%Aggregate{status: :submitted})
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a test's context pattern, block form" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits", %{aggregate: %Aggregate{status: status}} do
            status
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a test's context pattern, inline do: form" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits", %{aggregate: %Aggregate{status: status}}, do: status
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a struct literal built inside a test's body" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          test "submits", %{aggregate: aggregate} do
            %Aggregate{status: :submitted}
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "allows a struct literal in a setup's context pattern" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          setup %{aggregate: %Aggregate{status: status}} do
            {:ok, status: status}
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "allows a struct literal in a setup_all's context pattern" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          setup_all %{aggregate: %Aggregate{status: status}} do
            {:ok, status: status}
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "still reports a struct literal built inside a setup with no context argument" do
      [
        """
        defmodule Acme.Review.Domain.Aggregate do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
        """
        |> to_source_file("lib/acme/review/domain/aggregate.ex"),
        """
        defmodule Acme.Review.Domain.AggregateTest do
          use ExUnit.Case, async: true

          alias Acme.Review.Domain.Aggregate

          setup do
            {:ok, aggregate: %Aggregate{status: :submitted}}
          end
        end
        """
        |> to_source_file("test/acme/review/domain/aggregate_test.exs")
      ]
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end
  end

  describe "piped and reflected struct/2 and struct!/2 calls" do
    test "reports a piped struct/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Aggregate |> struct(status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a piped struct!/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Aggregate |> struct!(status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a piped Kernel.struct/2 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Aggregate |> Kernel.struct(status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report a piped struct/1 naming the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          Aggregate |> struct()
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a piped struct/2 given an empty list or map of fields" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          Aggregate |> struct([])
          Aggregate |> struct(%{})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "reports struct/2 reached through apply(Kernel, :struct, ...)" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          apply(Kernel, :struct, [Aggregate, status: attrs.status])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports struct!/2 reached through Kernel.apply(Kernel, :struct!, ...)" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Kernel.apply(Kernel, :struct!, [Aggregate, status: attrs.status])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports struct/2 captured as &struct(MyAggregate, &1)" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def builder, do: &struct(Aggregate, &1)
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report a bare &struct/2 capture, which names no module" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def builder, do: &struct/2
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report a defdelegate whose head pattern matches the aggregate" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        defdelegate describe(%Aggregate{status: status}), to: __MODULE__, as: :describe_status
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end
  end

  describe "struct/2 and struct!/2 calls given an empty aggregate struct as the target" do
    test "reports struct/2 given the empty struct literal as the first argument" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          struct(%Aggregate{}, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports struct!/2 given the empty struct literal as the first argument" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          struct!(%Aggregate{}, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports Kernel.struct/2 given the empty struct literal as the first argument" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Kernel.struct(%Aggregate{}, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a piped struct/2 given the empty struct literal as the target" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          %Aggregate{} |> struct(status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports a piped Kernel.struct/2 given the empty struct literal as the target" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          %Aggregate{} |> Kernel.struct(status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports struct/2 reached through apply(Kernel, :struct, ...) given the empty struct literal" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          apply(Kernel, :struct, [%Aggregate{}, status: attrs.status])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "reports struct!/2 reached through Kernel.apply(Kernel, :struct!, ...) given the empty struct literal" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run(attrs) do
          Kernel.apply(Kernel, :struct!, [%Aggregate{}, status: attrs.status])
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"
      end)
    end

    test "does not report struct/2 given the empty struct literal and empty fields, piped or not" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        alias Acme.Review.Domain.Aggregate

        def run do
          struct(%Aggregate{}, [])
          %Aggregate{} |> struct(%{})
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end

    test "does not report struct/2 given a variable that might hold an aggregate struct at runtime" do
      """
      defmodule Acme.Review.Domain.Aggregate do
        use Trogon.Commanded.Aggregate, identifier: :id
      end

      defmodule Acme.Review.Test do
        def run(existing_agg, attrs) do
          struct(existing_agg, status: attrs.status)
        end
      end
      """
      |> to_source_file()
      |> run_check(AggregateStateConstruction)
      |> refute_issues()
    end
  end
end
