defmodule Trogon.Credo.Check.Warning.RaiseStringTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Warning.RaiseString

  test "does not report a raise of an exception module" do
    """
    defmodule CredoSampleModule do
      def run do
        raise MyApp.NotFoundError
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "does not report a raise of an exception module with options" do
    """
    defmodule CredoSampleModule do
      def run(id) do
        raise MyApp.NotFoundError, id: id
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "does not report a raise of a struct" do
    """
    defmodule CredoSampleModule do
      def run do
        raise %MyApp.Error{}
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "does not report a raise of a variable" do
    """
    defmodule CredoSampleModule do
      def run(exception) do
        raise exception
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "does not report a raise of a function call" do
    """
    defmodule CredoSampleModule do
      def run do
        raise build_error()
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "does not report a raise of a module attribute" do
    """
    defmodule CredoSampleModule do
      @message "boom"

      def run do
        raise @message
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "reports a raise of a string literal" do
    """
    defmodule CredoSampleModule do
      def run do
        raise "boom"
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
      assert issue.message == "A `raise` must be given an exception, not a message string."
    end)
  end

  test "reports a raise of an interpolated string" do
    """
    defmodule CredoSampleModule do
      def run(id) do
        raise "no user \#{id}"
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "reports a raise of a concatenation with the literal on the left" do
    """
    defmodule CredoSampleModule do
      def run(id) do
        raise "no user " <> id
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "reports a raise of a concatenation with the literal on the right" do
    """
    defmodule CredoSampleModule do
      def run(id) do
        raise id <> " not found"
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "reports a raise of a string literal written with parentheses" do
    """
    defmodule CredoSampleModule do
      def run do
        raise("boom")
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
      assert issue.message == "A `raise` must be given an exception, not a message string."
    end)
  end

  test "reports a raise of a lowercase s sigil" do
    """
    defmodule CredoSampleModule do
      def run do
        raise ~s(boom)
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "reports a raise of an uppercase S sigil" do
    """
    defmodule CredoSampleModule do
      def run do
        raise ~S(boom)
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "reports every raise of a string in a file" do
    """
    defmodule CredoSampleModule do
      def first do
        raise "boom"
      end

      def second do
        raise "bang"
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issues(fn issues ->
      assert length(issues) == 2
    end)
  end

  test "does not report a reraise of a variable" do
    """
    defmodule CredoSampleModule do
      def run(exception) do
        reraise exception, __STACKTRACE__
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> refute_issues()
  end

  test "reports a reraise of a string literal" do
    """
    defmodule CredoSampleModule do
      def run do
        reraise "boom", __STACKTRACE__
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "reraise"
      assert issue.message == "A `reraise` must be given an exception, not a message string."
    end)
  end

  test "reports a raise written inside a quote block" do
    """
    defmodule MyApp.Macros do
      defmacro __using__(_opts) do
        quote do
          raise "boom"
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString)
    |> assert_issue(fn issue ->
      assert issue.trigger == "raise"
    end)
  end

  test "appends the hint to the message when configured" do
    """
    defmodule CredoSampleModule do
      def run do
        raise "boom"
      end
    end
    """
    |> to_source_file()
    |> run_check(RaiseString, hint: "Define an exception module and raise it instead.")
    |> assert_issue(fn issue ->
      assert issue.message ==
               "A `raise` must be given an exception, not a message string. Define an exception module and raise it instead."
    end)
  end
end
