defmodule Trogon.Credo.Check.Oban.WorkerNameTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Oban.WorkerName

  @message "Worker module `MyApp.SendWelcomeEmail` must end with `Worker`. If the worker is already deployed, jobs in " <>
             "`oban_jobs` store its current name, so keep that name working with `aliases:` on " <>
             "`use Oban.Pro.Worker` when renaming it."

  test "reports a worker whose name does not end with Worker" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue ->
      assert issue.check == WorkerName
      assert issue.category == WorkerName.category()
      assert issue.trigger == "MyApp.SendWelcomeEmail"
      assert issue.message == @message
      assert issue.line_no == 1
    end)
  end

  test "reports an Oban.Pro.Worker" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Oban.Pro.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue()
  end

  test "does not report a worker whose name ends with Worker" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "does not report a module that is not a worker" do
    """
    defmodule MyApp.Mailer do
      use GenServer
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "reports a nested worker under its full name" do
    """
    defmodule MyApp.Mailer do
      defmodule SendWelcomeEmail do
        use Oban.Worker, queue: :mailers
      end
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue ->
      assert issue.trigger == "SendWelcomeEmail"
      assert issue.message =~ "Worker module `MyApp.Mailer.SendWelcomeEmail` must end"
    end)
  end

  test "reports a worker that uses the worker module through an alias" do
    """
    defmodule MyApp.SendWelcomeEmail do
      alias Oban.Pro.Worker

      use Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue()
  end

  test "resolves a use through the aliases of its own module, not a sibling's" do
    """
    defmodule MyApp.Mailer do
      alias MyApp.Oban
    end

    defmodule MyApp.SendWelcomeEmail do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.SendWelcomeEmail" end)
  end

  test "resolves a use in a nested module through an alias of the enclosing one" do
    """
    defmodule MyApp.Mailer do
      alias Oban.Pro.Worker

      defmodule SendWelcomeEmail do
        use Worker, queue: :mailers
      end
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.trigger == "SendWelcomeEmail" end)
  end

  test "resolves a use through an alias written before the module" do
    """
    alias Oban.Pro.Worker

    defmodule MyApp.SendWelcomeEmail do
      use Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue()
  end

  test "does not resolve a use through an alias written after it" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Worker, queue: :mailers

      alias Oban.Pro.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "does not analyze a module defined inside a quote" do
    """
    defmodule MyApp.WorkerMacro do
      defmacro __using__(_opts) do
        quote do
          defmodule SendWelcomeEmail do
            use Oban.Worker, queue: :mailers
          end
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "uses the configured worker modules and suffix" do
    """
    defmodule MyApp.SendWelcomeEmailJob do
      use MyApp.Worker
    end

    defmodule MyApp.SendReceipt do
      use MyApp.Worker
    end

    defmodule MyApp.Cleanup do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, for_use: [MyApp.Worker], suffix: "Job")
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.SendReceipt"
      assert issue.message =~ "must end with `Job`"
    end)
  end

  test "reports nothing when for_use is empty" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, for_use: [])
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, hint: "See the workers guide.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " See the workers guide." end)
  end
end
