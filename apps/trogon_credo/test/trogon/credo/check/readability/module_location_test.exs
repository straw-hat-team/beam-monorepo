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

  test "does not report a use through a segment that is only known at compile time" do
    """
    defmodule MyApp.SendWelcomeEmail do
      use __MODULE__.Base
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs")
    |> refute_issues()
  end

  test "does not attribute a use written inside a quote block to the enclosing module" do
    """
    defmodule MyApp.Macros do
      defmacro build do
        quote do
          use Oban.Worker
        end
      end
    end
    """
    |> to_source_file("lib/my_app/macros.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs", namespace_segment: :Jobs)
    |> refute_issues()
  end

  test "does not check the namespace of a module whose namespace is only known at compile time" do
    """
    defmodule MyApp.Jobs do
      defmodule __MODULE__.SendEmail do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: :Workers)
    |> refute_issues()
  end

  test "still checks the path of a module whose namespace is only known at compile time" do
    """
    defmodule MyApp.Jobs do
      defmodule __MODULE__.SendEmail do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs", namespace_segment: :Workers)
    |> assert_issue(fn issue -> assert issue.message =~ "`jobs/` directory" end)
  end

  test "does not attribute a use inside a module named by an atom to the enclosing namespace" do
    """
    defmodule MyApp.Workers do
      defmodule :my_worker do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/workers/my_worker.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: :Workers)
    |> assert_issue(fn issue -> assert issue.message =~ "namespace containing `Workers`" end)
  end

  test "does not check the namespace of a module whose name is built by a call" do
    """
    defmodule MyApp.Jobs do
      defmodule Module.concat(Foo, Bar) do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: :Workers)
    |> refute_issues()
  end

  test "does not append anything to the message by default" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: "jobs")
    |> assert_issue(fn issue ->
      assert issue.message == "Modules that use `Oban.Worker` must live under a `jobs/` directory."
    end)
  end

  test "appends the hint to a path issue" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      path_segment: "jobs",
      hint: "Move it under lib/my_app/jobs/."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Modules that use `Oban.Worker` must live under a `jobs/` directory. Move it under lib/my_app/jobs/."
    end)
  end

  test "appends the hint to a namespace issue" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation,
      for_use: [Oban.Worker],
      namespace_segment: :Jobs,
      hint: "Rename it to MyApp.Jobs.SendEmail."
    )
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Modules that use `Oban.Worker` must be in a namespace containing `Jobs`. Rename it to MyApp.Jobs.SendEmail."
    end)
  end

  test "accepts a list of path_segment alternatives, matching one of them" do
    """
    defmodule MyApp.Workers.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/workers/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: ["jobs", "workers"])
    |> refute_issues()
  end

  test "reports a module matching none of the path_segment alternatives" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: ["jobs", "workers"])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Modules that use `Oban.Worker` must live under one of these directories: `jobs/`, `workers/`."
    end)
  end

  test "accepts a namespace_segment pinned to a positive position" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Jobs, 2})
    |> refute_issues()
  end

  test "reports a module whose segment at a positive position does not match" do
    """
    defmodule MyApp.Workers.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Jobs, 2})
    |> assert_issue(fn issue ->
      assert issue.message == "Modules that use `Oban.Worker` must be in a namespace with `Jobs` as segment 2."
    end)
  end

  test "accepts a namespace_segment pinned to a negative position" do
    """
    defmodule MyApp.SendEmail.Jobs do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Jobs, -1})
    |> refute_issues()
  end

  test "reports a module whose segment at a negative position does not match" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Jobs, -1})
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Modules that use `Oban.Worker` must be in a namespace with `Jobs` as segment 1 counting from the end."
    end)
  end

  test "does not match a position that falls outside the namespace" do
    """
    defmodule MyApp.Jobs.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Jobs, 5})
    |> assert_issue(fn issue ->
      assert issue.message == "Modules that use `Oban.Worker` must be in a namespace with `Jobs` as segment 5."
    end)
  end

  test "accepts a mixed list of namespace_segment rules, matching the second one" do
    """
    defmodule MyApp.Workers.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: [:Jobs, {:Workers, 2}])
    |> refute_issues()
  end

  test "reports a module matching none of a mixed list of namespace_segment rules" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: [:Jobs, {:Processor, 3}])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Modules that use `Oban.Worker` must be in a namespace containing `Jobs`, or a namespace with `Processor` as segment 3."
    end)
  end

  test "does not check a positional namespace_segment rule against a compile-time namespace" do
    """
    defmodule MyApp.Jobs do
      defmodule __MODULE__.SendEmail do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/jobs/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: {:Workers, 1})
    |> refute_issues()
  end

  test "treats an empty path_segment list the same as nil" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], path_segment: [])
    |> refute_issues()
  end

  test "treats an empty namespace_segment list the same as nil" do
    """
    defmodule MyApp.SendEmail do
      use Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_email.ex")
    |> run_check(ModuleLocation, for_use: [Oban.Worker], namespace_segment: [])
    |> refute_issues()
  end

  test "raises when a namespace_segment tuple's position is not a non-zero integer" do
    source_file =
      """
      defmodule MyApp.SendEmail do
        use Oban.Worker
      end
      """
      |> to_source_file("lib/my_app/send_email.ex")

    assert_raise ArgumentError, ~r/invalid namespace_segment {:Jobs, 0}/, fn ->
      ModuleLocation.run(source_file, for_use: [Oban.Worker], namespace_segment: {:Jobs, 0})
    end
  end
end
