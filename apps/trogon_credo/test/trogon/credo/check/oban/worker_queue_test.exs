defmodule Trogon.Credo.Check.Oban.WorkerQueueTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Oban.WorkerQueue

  test "reports use Oban.Worker without queue" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Worker, max_attempts: 3
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue)
    |> assert_issue(fn issue ->
      assert issue.check == WorkerQueue
      assert issue.category == WorkerQueue.category()
      assert issue.trigger == "Oban.Worker"
      assert issue.message == "The `use Oban.Worker` must set the `queue:` option."
    end)
  end

  test "reports use Oban.Pro.Worker without options" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Pro.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue)
    |> assert_issue(fn issue -> assert issue.trigger == "Oban.Pro.Worker" end)
  end

  test "does not report a worker that sets queue" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Worker, queue: :mailers
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue)
    |> refute_issues()
  end

  test "does not report the use of another module" do
    """
    defmodule MyApp.Server do
      use GenServer
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue)
    |> refute_issues()
  end

  test "reports only the configured worker modules when for_use is set" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use MyApp.Worker
    end

    defmodule MyApp.SendReceiptWorker do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue, for_use: [MyApp.Worker])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Worker" end)
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(WorkerQueue, hint: "See the queues guide.")
    |> assert_issue(fn issue ->
      assert issue.message == "The `use Oban.Worker` must set the `queue:` option. See the queues guide."
    end)
  end
end
