defmodule Trogon.Credo.Check.Readability.OneModulePerFileTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.OneModulePerFile

  test "does not report a file with a single module" do
    """
    defmodule MyApp.Invoice do
      defstruct [:id]
    end
    """
    |> to_source_file("lib/my_app/invoice.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "reports every module after the first in a file" do
    """
    defmodule MyApp.A do
    end

    defmodule MyApp.B do
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue ->
      assert issue.line_no == 4
      assert issue.message == "The module `MyApp.B` is expected to be the only one in its file."
    end)
  end

  test "reports each extra module of a file with three" do
    """
    defmodule MyApp.A do
    end

    defmodule MyApp.B do
    end

    defmodule MyApp.C do
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(OneModulePerFile)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "reports a nested module" do
    """
    defmodule MyApp.Invoice do
      defmodule Line do
        defstruct [:amount]
      end
    end
    """
    |> to_source_file("lib/my_app/invoice.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message == "The module `Line` is expected to be the only one in its file."
    end)
  end

  test "reports a module sharing its file with an exception" do
    """
    defmodule MyApp.Error do
      defexception [:message]
    end

    defmodule MyApp.Other do
    end
    """
    |> to_source_file("lib/my_app/error.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "ignores a defmodule inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro __using__(_opts) do
        quote do
          defmodule Generated do
            defstruct [:id]
          end
        end
      end
    end
    """
    |> to_source_file("lib/my_app/macros.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "ignores a defmodule inside a test block" do
    """
    defmodule MyAppTest do
      use ExUnit.Case

      test "uses the macro" do
        defmodule Dummy do
          use MyApp.Thing
        end
      end
    end
    """
    |> to_source_file("test/my_app_test.exs")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "ignores a defmodule inside a def" do
    """
    defmodule MyApp.Builder do
      def build do
        defmodule Built do
        end
      end
    end
    """
    |> to_source_file("lib/my_app/builder.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "ignores a defmodule inside an anonymous function" do
    """
    defmodule MyApp.Builder do
      @builder fn ->
        defmodule Built do
        end
      end
    end
    """
    |> to_source_file("lib/my_app/builder.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "reports a defmodule inside a describe block but outside a test" do
    """
    defmodule MyAppTest do
      use ExUnit.Case

      describe "thing" do
        defmodule Helper do
        end
      end
    end
    """
    |> to_source_file("test/my_app_test.exs")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "reports a defmodule inside a top-level if in a module body" do
    """
    defmodule MyApp.Conditional do
      if Code.ensure_loaded?(Foo) do
        defmodule Bridge do
        end
      end
    end
    """
    |> to_source_file("lib/my_app/conditional.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "ignores a defmodule inside a capture" do
    """
    defmodule MyApp.Builder do
      @builder &{&1, defmodule(Built, do: nil)}
    end
    """
    |> to_source_file("lib/my_app/builder.ex")
    |> run_check(OneModulePerFile)
    |> refute_issues()
  end

  test "reports a defmodule in a module attribute named like a runtime scope" do
    """
    defmodule MyApp.Attribute do
      @setup (defmodule Helper do
      end)
    end
    """
    |> to_source_file("lib/my_app/attribute.ex")
    |> run_check(OneModulePerFile)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.A do
    end

    defmodule MyApp.B do
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(OneModulePerFile, hint: "Move it.")
    |> assert_issue(fn issue -> assert String.ends_with?(issue.message, " Move it.") end)
  end
end
