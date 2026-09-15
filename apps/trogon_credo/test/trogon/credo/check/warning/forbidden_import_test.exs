defmodule Trogon.Credo.Check.Warning.ForbiddenImportTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.ForbiddenImport

  test "does not report modules that are not imported" do
    """
    defmodule CredoSampleModule do
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [SomeModule])
    |> refute_issues()
  end

  test "does not report plain calls to a forbidden module" do
    """
    defmodule CredoSampleModule do
      def run do
        MyApp.Fixtures.build_user()
      end
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [MyApp.Fixtures])
    |> refute_issues()
  end

  test "reports a plain import of a forbidden module" do
    """
    defmodule CredoSampleModule do
      import MyApp.Fixtures
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [MyApp.Fixtures])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Fixtures"
      assert issue.message == "The `MyApp.Fixtures` module must not be imported."
    end)
  end

  test "reports each forbidden member of a multi-import" do
    """
    defmodule CredoSampleModule do
      import Foo.{Bar, Baz}
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [Foo.Bar])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Bar"
    end)
  end

  test "reports every forbidden member of a multi-import" do
    """
    defmodule CredoSampleModule do
      import Foo.{Bar, Baz}
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [Foo.Bar, Foo.Baz])
    |> assert_issues(fn issues ->
      assert Enum.count(issues) == 2
      assert Enum.map(issues, & &1.trigger) |> Enum.sort() == ["Bar", "Baz"]
    end)
  end

  test "reports an import with only:" do
    """
    defmodule CredoSampleModule do
      import MyApp.Fixtures, only: [:build_user]
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [MyApp.Fixtures])
    |> assert_issue(fn issue ->
      assert issue.trigger == "MyApp.Fixtures"
    end)
  end

  test "uses a custom message when configured" do
    """
    defmodule CredoSampleModule do
      import MyApp.Fixtures
    end
    """
    |> to_source_file()
    |> run_check(ForbiddenImport, modules: [{MyApp.Fixtures, "Use MyApp.Fixtures functions with the full name."}])
    |> assert_issue(fn issue ->
      assert issue.message == "Use MyApp.Fixtures functions with the full name."
    end)
  end
end
