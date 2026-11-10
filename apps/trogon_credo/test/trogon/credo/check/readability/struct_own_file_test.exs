defmodule Trogon.Credo.Check.Readability.StructOwnFileTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Readability.StructOwnFile

  test "does not report a file whose only module defines the struct" do
    """
    defmodule MyApp.Invoice do
      defstruct [:id]
    end
    """
    |> to_source_file("lib/my_app/invoice.ex")
    |> run_check(StructOwnFile)
    |> refute_issues()
  end

  test "does not report a file with several modules and no struct" do
    """
    defmodule MyApp.A do
    end

    defmodule MyApp.B do
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(StructOwnFile)
    |> refute_issues()
  end

  test "reports a struct sharing its file with a sibling module" do
    """
    defmodule MyApp.Invoice do
      defstruct [:id]
    end

    defmodule MyApp.Receipt do
    end
    """
    |> to_source_file("lib/my_app/invoice.ex")
    |> run_check(StructOwnFile)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message == "A `defstruct` is expected to be the only module in its file."
    end)
  end

  test "reports a struct in a nested module" do
    """
    defmodule MyApp.Invoice do
      defmodule Line do
        defstruct [:amount]
      end
    end
    """
    |> to_source_file("lib/my_app/invoice.ex")
    |> run_check(StructOwnFile)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "reports every struct of a shared file" do
    """
    defmodule MyApp.A do
      defstruct [:a]
    end

    defmodule MyApp.B do
      defstruct [:b]
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(StructOwnFile)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "ignores a defstruct and a defmodule inside a quote block" do
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
    |> run_check(StructOwnFile)
    |> refute_issues()
  end

  test "reports a defexception sharing its file with another module" do
    """
    defmodule MyApp.Error do
      defexception [:message]
    end

    defmodule MyApp.Other do
    end
    """
    |> to_source_file("lib/my_app/error.ex")
    |> run_check(StructOwnFile)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message == "A `defexception` is expected to be the only module in its file."
    end)
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.A do
      defstruct [:a]
    end

    defmodule MyApp.B do
    end
    """
    |> to_source_file("lib/my_app/a.ex")
    |> run_check(StructOwnFile, hint: "Move it.")
    |> assert_issue(fn issue -> assert String.ends_with?(issue.message, " Move it.") end)
  end
end
