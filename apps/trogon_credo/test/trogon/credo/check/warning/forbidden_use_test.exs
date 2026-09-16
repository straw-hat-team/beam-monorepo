defmodule Trogon.Credo.Check.Warning.ForbiddenUseTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.ForbiddenUse

  test "does not report a module that is not used" do
    """
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report a use of a module that is not configured" do
    """
    defmodule CredoSampleModule do
      use GenServer
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report plain calls to a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Client.get("/things")
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report an import of a forbidden module" do
    """
    defmodule CredoSampleModule do
      import MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report a module whose name only ends with a forbidden segment" do
    """
    defmodule CredoSampleModule do
      use Vendor.MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "reports a plain use of a forbidden module" do
    """
    defmodule CredoSampleModule do
      use MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Client"
      assert issue.message == "The `MyApp.Client` module must not be brought in with `use`."
    end)
  end

  test "reports a use written with options" do
    """
    defmodule CredoSampleModule do
      use MyApp.Client, only: [:get]
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Client"
    end)
  end

  test "reports every forbidden use in a file" do
    """
    defmodule CredoSampleModule do
      defmodule First do
        use MyApp.Client
      end

      defmodule Second do
        use MyApp.Client
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "uses a custom message when configured" do
    """
    defmodule CredoSampleModule do
      use MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [{MyApp.Client, "Build a client with MyApp.Client.new/1 instead."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Build a client with MyApp.Client.new/1 instead."
    end)
  end

  test "reports a use resolved through an alias" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Client
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Client"
      assert issue.message == "The `MyApp.Client` module must not be brought in with `use`."
    end)
  end

  test "reports a use resolved through a renamed alias" do
    """
    defmodule CredoSampleModule do
      alias MyApp.Client, as: HTTP
      use HTTP
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "HTTP"
    end)
  end

  test "reports a use resolved through a multi alias" do
    """
    defmodule CredoSampleModule do
      alias MyApp.{Client, Repo}
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Client"
    end)
  end

  test "reports a use resolved through a multi alias written with options" do
    """
    defmodule CredoSampleModule do
      alias MyApp.{Client, Repo}, warn: false
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Client"
    end)
  end

  test "reports a use written with an explicit Elixir prefix" do
    """
    defmodule CredoSampleModule do
      use Elixir.MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Elixir.MyApp.Client"
      assert issue.message == "The `MyApp.Client` module must not be brought in with `use`."
    end)
  end

  test "reports a use written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro __using__(_opts) do
        quote do
          use MyApp.Client
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Client"
    end)
  end

  test "is not resolved through an alias written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro __using__(_opts) do
        quote do
          alias MyApp.Client
          use Client
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report a use whose module is only known at compile time" do
    """
    defmodule MyApp.Macros do
      defmacro build(module) do
        quote do
          use unquote(module)
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report a use through a segment that is only known at compile time" do
    """
    defmodule MyApp.Runner do
      use __MODULE__.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "does not report a use through a name that sibling modules bind to different modules" do
    """
    defmodule A do
      alias Vendor.Client
      use Client
    end

    defmodule B do
      alias MyApp.Client
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> refute_issues()
  end

  test "still reports a use through a name that sibling modules bind to the same module" do
    """
    defmodule A do
      alias MyApp.Client
      use Client
    end

    defmodule B do
      alias MyApp.Client
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [MyApp.Client])
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "is inert when no module is configured" do
    """
    defmodule CredoSampleModule do
      use MyApp.Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse)
    |> refute_issues()
  end

  test "does not report an ambiguous name as the module it is written as" do
    """
    defmodule A do
      alias Vendor.Client
      use Client
    end

    defmodule B do
      alias MyApp.Client
      use Client
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenUse, modules: [Client])
    |> refute_issues()
  end
end
