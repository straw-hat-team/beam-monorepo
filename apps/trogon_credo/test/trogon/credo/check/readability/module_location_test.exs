defmodule Trogon.Credo.Check.Readability.ModuleLocationTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.ModuleLocation

  test "does not report a module in the expected path and namespace" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      path_segment: "jobs",
      namespace_segment: :Jobs
    )
    |> refute_issues()
  end

  test "reports a module living outside the expected directory" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      path_segment: "jobs",
      namespace_segment: :Jobs
    )
    |> assert_issue(fn issue -> assert issue.message =~ "must live under" end)
  end

  test "reports a module outside the expected namespace" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      path_segment: "jobs",
      namespace_segment: :Jobs
    )
    |> assert_issue(fn issue -> assert issue.message =~ "must be in a namespace" end)
  end

  test "reports a single path issue when both the path and namespace are wrong" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      path_segment: "jobs",
      namespace_segment: :Jobs
    )
    |> assert_issue(fn issue -> assert issue.message =~ "must live under" end)
  end

  test "is inert when for_use is left as the default empty list" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, path_segment: "jobs", namespace_segment: :Jobs)
    |> refute_issues()
  end

  test "ignores a module that does not use any for_use module" do
    """
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Some.Behaviour], path_segment: "jobs")
    |> refute_issues()
  end

  test "accepts namespace_segment configured as a string" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: "Jobs")
    |> refute_issues()
  end

  test "accumulates the namespace of a nested defmodule" do
    """
    defmodule MyApp do
      defmodule Jobs.SendEmail do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: :Jobs)
    |> refute_issues()
  end

  test "uses the used module as the trigger" do
    """
    defmodule MyApp.Jobs.SendWelcomeEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs")
    |> assert_issue(fn issue -> assert issue.trigger == "Oban.Worker" end)
  end

  test "applies to a use written with an explicit Elixir prefix" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use Elixir.Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs")
    |> assert_issue(fn issue ->
      assert issue.message =~ "must live under a `jobs/` directory"
    end)
  end

  test "applies to a use written through an alias" do
    """
    defmodule MyApp.SendWelcomeEmail do
      alias Oban.Worker

      use Worker
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs")
    |> assert_issue()
  end
end
