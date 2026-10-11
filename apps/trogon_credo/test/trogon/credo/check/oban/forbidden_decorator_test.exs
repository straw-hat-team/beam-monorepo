defmodule Trogon.Credo.Check.Oban.ForbiddenDecoratorTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Oban.ForbiddenDecorator

  @message "Define an `Oban.Pro.Worker` for the job instead of decorating a function with `Oban.Pro.Decorator`."

  test "reports use Oban.Pro.Decorator" do
    """
    defmodule MyApp.Mailer do
      use Oban.Pro.Decorator
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenDecorator)
    |> assert_issue(fn issue ->
      assert issue.check == ForbiddenDecorator
      assert issue.category == ForbiddenDecorator.category()
      assert issue.trigger == "Oban.Pro.Decorator"
      assert issue.message == @message
    end)
  end

  test "reports a use written through an alias" do
    """
    defmodule MyApp.Mailer do
      alias Oban.Pro.Decorator

      use Decorator
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenDecorator)
    |> assert_issue(fn issue -> assert issue.trigger == "Decorator" end)
  end

  test "does not report a worker" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Pro.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenDecorator)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Mailer do
      use Oban.Pro.Decorator
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenDecorator, hint: "See the jobs guide.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " See the jobs guide." end)
  end
end
