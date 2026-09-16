defmodule Trogon.Credo.Check.Readability.MechanicalModuleNameTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.MechanicalModuleName

  test "does not report a module named after its domain role" do
    """
    defmodule MyApp.Jobs.SendWelcomeEmail do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName)
    |> refute_issues()
  end

  test "applies to every module when for_use is left as the default empty list" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName)
    |> assert_issue()
  end

  for suffix <- ~w(Worker Job Manager Helper Util Utils) do
    test "reports a module name ending in the default suffix #{suffix}" do
      """
      defmodule MyApp.SendWelcomeEmail#{unquote(suffix)} do
      end
      """
      |> to_source_file()
      |> run_check(MechanicalModuleName)
      |> assert_issue(fn issue -> assert issue.message =~ unquote(suffix) end)
    end
  end

  test "only applies to modules that use one of the configured for_use modules" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Oban.Worker
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker])
    |> assert_issue()
  end

  test "ignores a mechanical module name when it does not use any configured for_use module" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker])
    |> refute_issues()
  end

  test "accepts a custom suffixes list" do
    """
    defmodule MyApp.SendWelcomeEmailRunner do
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, suffixes: ["Runner"])
    |> assert_issue(fn issue -> assert issue.message =~ "Runner" end)
  end

  test "does not reject the default suffixes once a custom suffixes list is configured" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, suffixes: ["Runner"])
    |> refute_issues()
  end

  test "reports a file name ending in a mechanical suffix" do
    """
    defmodule MyApp.SendWelcomeEmail do
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email_worker.ex")
    |> run_check(MechanicalModuleName)
    |> assert_issue(fn issue -> assert issue.message =~ "File name" end)
  end

  test "reports only the module name violation when both the module and file names are mechanical" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email_worker.ex")
    |> run_check(MechanicalModuleName)
    |> assert_issue(fn issue -> assert issue.message =~ "Module name" end)
  end

  test "reports the file name once for a file holding several well named modules" do
    """
    defmodule MyApp.SendWelcomeEmail do
    end

    defmodule MyApp.CancelOrder do
    end

    defmodule MyApp.RefundOrder do
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email_worker.ex")
    |> run_check(MechanicalModuleName)
    |> assert_issue(fn issue -> assert issue.message =~ "File name" end)
  end

  test "reports the module name at the defmodule line with the module name as the trigger" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName)
    |> assert_issue(fn issue ->
      assert issue.line_no == 1
      assert issue.trigger == "MyApp.SendWelcomeEmailWorker"
    end)
  end

  test "reports a nested module named after its mechanism" do
    """
    defmodule MyApp do
      defmodule SendWelcomeEmailWorker do
      end
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "SendWelcomeEmailWorker"
    end)
  end

  test "narrows to the nested module that uses the configured for_use module" do
    """
    defmodule MyApp do
      defmodule SendWelcomeEmailWorker do
        use Oban.Worker
      end

      defmodule CancelOrderWorker do
      end
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker])
    |> assert_issue(fn issue -> assert issue.trigger == "SendWelcomeEmailWorker" end)
  end

  test "applies to a use written with an explicit Elixir prefix" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use Elixir.Oban.Worker
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email_worker.ex")
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.SendWelcomeEmailWorker"
    end)
  end

  test "applies to a use written through an alias" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      alias Oban.Worker

      use Worker
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> assert_issue()
  end

  test "does not report a use through a segment that is only known at compile time" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      use __MODULE__.Base
    end
    """
    |> to_source_file()
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> refute_issues()
  end

  test "does not attribute a use written inside a quote block to the enclosing module" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      defmacro build do
        quote do
          use Oban.Worker
        end
      end
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email_worker.ex")
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> refute_issues()
  end

  test "does not resolve a use through an alias written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro build do
        quote do
          alias Oban.Worker
        end
      end
    end

    defmodule MyApp.SendWelcomeEmailWorker do
      use Worker
    end
    """
    |> to_source_file("lib/my_app/macros.ex")
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> refute_issues()
  end

  test "does not attribute a use inside a module named by an atom to the enclosing module" do
    """
    defmodule MyApp.SendWelcomeEmailWorker do
      defmodule :helper do
        use Oban.Worker
      end
    end
    """
    |> to_source_file("lib/my_app/send_welcome_email.ex")
    |> run_check(MechanicalModuleName, for_use: [Oban.Worker], suffixes: ["Worker"])
    |> refute_issues()
  end
end
