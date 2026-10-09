defmodule Trogon.Credo.Check.Oban.WorkerNameTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Oban.WorkerName

  @message "Worker module `MyApp.Billing.InvoiceReminderWorker` ends with `Worker`, which names the mechanism " <>
             "that runs it instead of the action it performs. Drop the suffix and name the module after what " <>
             "it does. If the worker is already deployed, jobs in `oban_jobs` store its current name, so keep " <>
             "that name working with `aliases:` on `use Oban.Pro.Worker` when renaming it."

  test "reports a worker whose name ends with Worker" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue ->
      assert issue.check == WorkerName
      assert issue.category == WorkerName.category()
      assert issue.trigger == "MyApp.Billing.InvoiceReminderWorker"
      assert issue.message == @message
      assert issue.line_no == 1
    end)
  end

  test "reports a worker whose name ends with Processor" do
    """
    defmodule MyApp.Billing.InvoiceReminderProcessor do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.message =~ "ends with `Processor`" end)
  end

  test "reports an Oban.Pro.Worker" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Pro.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue()
  end

  test "does not report a worker named after the action it performs" do
    """
    defmodule MyApp.Billing.InvoiceReminder do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "does not report a worker named with an action verb phrase" do
    """
    defmodule MyApp.Mailer.SendWelcomeEmail do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> refute_issues()
  end

  test "does not report a module that is not a worker" do
    """
    defmodule MyApp.MailerWorker do
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
      defmodule WelcomeEmailSenderWorker do
        use Oban.Worker, queue: :mailers
      end
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue ->
      assert issue.trigger == "WelcomeEmailSenderWorker"
      assert issue.message =~ "Worker module `MyApp.Mailer.WelcomeEmailSenderWorker` ends with"
    end)
  end

  test "reports a worker that uses the worker module through an alias" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
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

    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Billing.InvoiceReminderWorker" end)
  end

  test "resolves a use in a nested module through an alias of the enclosing one" do
    """
    defmodule MyApp.Mailer do
      alias Oban.Pro.Worker

      defmodule WelcomeEmailSenderWorker do
        use Worker, queue: :mailers
      end
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.trigger == "WelcomeEmailSenderWorker" end)
  end

  test "resolves a use through an alias written before the module" do
    """
    alias Oban.Pro.Worker

    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName)
    |> assert_issue()
  end

  test "does not resolve a use through an alias written after it" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
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
          defmodule WelcomeEmailSenderWorker do
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

  test "reports a file name ending in a mechanism suffix" do
    """
    defmodule MyApp.Billing.InvoiceReminder do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file("lib/my_app/billing/invoice_reminder_worker.ex")
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.message =~ "File name" end)
  end

  test "reports a file name ending in the Processor suffix" do
    """
    defmodule MyApp.Billing.InvoiceReminder do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file("lib/my_app/billing/invoice_reminder_processor.ex")
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.message =~ "ends with the mechanism suffix `Processor`" end)
  end

  test "reports only the module name violation when both the module and file names are mechanical" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file("lib/my_app/billing/invoice_reminder_worker.ex")
    |> run_check(WorkerName)
    |> assert_issue(fn issue -> assert issue.message =~ "Worker module" end)
  end

  test "uses the configured worker modules and suffixes" do
    """
    defmodule MyApp.Billing.InvoiceReminderJob do
      use MyApp.Worker
    end

    defmodule MyApp.Billing.RefundOrder do
      use MyApp.Worker
    end

    defmodule MyApp.Cleanup do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, for_use: [MyApp.Worker], suffixes: ["Job"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Billing.InvoiceReminderJob"
      assert issue.message =~ "ends with `Job`"
    end)
  end

  test "reports nothing when for_use is empty" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, for_use: [])
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Billing.InvoiceReminderWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerName, hint: "See the workers guide.")
    |> assert_issue(fn issue -> assert issue.message == @message <> " See the workers guide." end)
  end
end
