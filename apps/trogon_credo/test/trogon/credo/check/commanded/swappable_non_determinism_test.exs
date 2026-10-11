defmodule Trogon.Credo.Check.Commanded.SwappableNonDeterminismTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Commanded.SwappableNonDeterminism

  @message "Call a component the project can swap instead of calling this directly, " <>
             "since a processor may depend on time, randomness, or ids only through a " <>
             "seam a test can replace."

  test "does not report anything when no module uses a processor module" do
    """
    defmodule Acme.Billing.Plain do
      def run do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> refute_issues()
  end

  test "reports a qualified call inside an event handler" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> assert_issue(fn issue ->
      assert issue.check == SwappableNonDeterminism
      assert issue.category == SwappableNonDeterminism.category()
      assert issue.trigger == "DateTime.utc_now"
      assert issue.message == @message
    end)
  end

  test "reports a call through an alias" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__
      alias Ecto.UUID

      def handle(event, _metadata) do
        UUID.generate()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> assert_issue(fn issue -> assert issue.trigger == "UUID.generate" end)
  end

  test "reports a captured call" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        &DateTime.utc_now/0
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end

  test "reports a piped call" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        event |> Map.get(:id) |> DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end

  test "reports a whole module entry such as :rand" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        :rand.uniform()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> assert_issue(fn issue -> assert issue.trigger == ":rand.uniform" end)
  end

  test "does not report the swappable component itself" do
    """
    defmodule Acme.Clock do
      def utc_now, do: DateTime.utc_now()
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> refute_issues()
  end

  test "does not scope the file when the use is written inside a quote block" do
    """
    defmodule Acme.Billing.EventHandler do
      defmacro __using__(_opts) do
        quote do
          use Commanded.Event.Handler, application: Acme.App, name: __MODULE__
        end
      end

      def handle(event, _metadata) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism, hint: "Use Acme.Clock.utc_now/0.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " Use Acme.Clock.utc_now/0." end)
  end

  test "reports only the configured calls when calls is set" do
    """
    defmodule Acme.Billing.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        DateTime.utc_now()
        MyApp.Ids.next()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism, calls: [{MyApp.Ids, :next}])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Ids.next" end)
  end

  test "accepts custom processor_modules" do
    """
    defmodule Acme.Billing.Worker do
      use Oban.Pro.Worker

      def process(_job) do
        DateTime.utc_now()
      end
    end
    """
    |> to_source_file()
    |> run_check(SwappableNonDeterminism, processor_modules: [Oban.Pro.Worker])
    |> assert_issue(fn issue -> assert issue.trigger == "DateTime.utc_now" end)
  end
end
