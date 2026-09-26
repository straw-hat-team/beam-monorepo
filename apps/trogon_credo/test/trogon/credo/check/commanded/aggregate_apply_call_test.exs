defmodule Trogon.Credo.Check.Commanded.AggregateApplyCallTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.AggregateApplyCall

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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Aggregate"

        assert issue.message ==
                 "Dispatch a command through the command handler instead of calling " <>
                   "`Acme.Review.Domain.Aggregate.apply/2` directly, since that bypasses the command handler " <>
                   "and can build a state the handler could never produce."
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall, aggregate_modules: [Acme.Aggregate])
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
      |> run_check(AggregateApplyCall, hint: "Use the command handler case in tests instead.")
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall, command_handler_modules: [Acme.CommandHandler])
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
      |> run_check(AggregateApplyCall)
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
      |> run_check(AggregateApplyCall, command_handler_case: Acme.CommandHandlerCase)
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
      |> run_check(AggregateApplyCall)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Extract the shared logic into a private function"
      end)
    end
  end
end
