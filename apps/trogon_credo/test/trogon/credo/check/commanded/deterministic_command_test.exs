defmodule Trogon.Credo.Check.Commanded.DeterministicCommandTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.DeterministicCommand

  @message "Put the value on the command instead of drawing it inside the aggregate or " <>
             "command handler, since a command is decided from the aggregate state and " <>
             "the command alone."

  test "does not report anything when no module uses an aggregate or command handler module" do
    """
    defmodule Acme.Billing.Plain do
      def run do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> refute_issues()
  end

  test "reports a qualified call inside an aggregate" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue ->
      assert issue.check == DeterministicCommand
      assert issue.category == DeterministicCommand.category()
      assert issue.trigger == "DateTime.utc_now"
      assert issue.message == @message
    end)
  end

  test "reports a call inside a command handler" do
    """
    defmodule Acme.Billing.CommandHandler do
      use Trogon.Commanded.CommandHandler, aggregate: Acme.Billing.Aggregate

      def handle(aggregate, command) do
        Ecto.UUID.generate()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue -> assert issue.trigger == "Ecto.UUID.generate" end)
  end

  test "reports a call through an alias" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id
      alias Ecto.UUID

      def execute(aggregate, command) do
        UUID.generate()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue -> assert issue.trigger == "UUID.generate" end)
  end

  test "reports a captured call" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        &DateTime.utc_now/0
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end

  test "reports a piped call" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        command |> Map.get(:id) |> DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end

  test "reports a whole module entry such as :rand" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        :rand.uniform()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> assert_issue(fn issue -> assert issue.trigger == ":rand.uniform" end)
  end

  test "does not scope the file when the use is written inside a quote block" do
    """
    defmodule Acme.Billing.Aggregate do
      defmacro __using__(_opts) do
        quote do
          use Trogon.Commanded.Aggregate, identifier: :id
        end
      end

      def execute(aggregate, command) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand, hint: "Read it from command.issued_at instead.")
    |> assert_issue(fn issue ->
      assert issue.message == @message <> " Read it from command.issued_at instead."
    end)
  end

  test "reports only the configured calls when calls is set" do
    """
    defmodule Acme.Billing.Aggregate do
      use Trogon.Commanded.Aggregate, identifier: :id

      def execute(aggregate, command) do
        DateTime.utc_now()
        MyApp.Ids.next()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand, calls: [{MyApp.Ids, :next}])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Ids.next" end)
  end

  test "accepts custom aggregate_modules" do
    """
    defmodule Acme.Billing.Aggregate do
      use Acme.Aggregate

      def execute(aggregate, command) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand, aggregate_modules: [Acme.Aggregate])
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end

  test "accepts custom command_handler_modules" do
    """
    defmodule Acme.Billing.CommandHandler do
      use Acme.CommandHandler

      def handle(aggregate, command) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(DeterministicCommand, command_handler_modules: [Acme.CommandHandler])
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end
end
