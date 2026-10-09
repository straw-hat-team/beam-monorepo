defmodule Trogon.Credo.Check.Dispatcher.StructConstructionTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Dispatcher.StructConstruction

  test "reports a bare DispatchOptions struct literal" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        %DispatchOptions{actor: actor, assigns: %{}}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> assert_issue(fn issue ->
      assert issue.check == StructConstruction
      assert issue.category == StructConstruction.category()
      assert issue.trigger == "DispatchOptions"
      assert issue.message =~ "DispatchOptions.new/1"
      assert issue.message =~ "new!/1"
    end)
  end

  test "reports a fully qualified DispatchOptions struct literal" do
    """
    defmodule MyApp.Authorize do
      def build(actor) do
        %Trogon.Dispatcher.DispatchOptions{actor: actor}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Trogon.Dispatcher.DispatchOptions"
    end)
  end

  test "reports a bare Context struct literal" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.Context

      def build(message) do
        %Context{message: message, kind: :command, dispatcher: nil, registered_by: nil}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Context"
      assert issue.message =~ "Context.new/3"
      refute issue.message =~ "Trogon.Dispatcher.Test"
    end)
  end

  test "reports a Context struct literal in a test file naming Trogon.Dispatcher.Test" do
    """
    defmodule MyApp.AuthorizeTest do
      alias Trogon.Dispatcher.Context

      def build(message) do
        %Context{message: message, kind: :command, dispatcher: nil, registered_by: nil}
      end
    end
    """
    |> to_source_file("authorize_test.exs")
    |> run_check(StructConstruction)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Context.new/3"
      assert issue.message =~ "Trogon.Dispatcher.Test"
      assert issue.message =~ "build_context/3"
    end)
  end

  test "does not report a struct update form" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.Context

      def touch(context) do
        %Context{context | response: :ok}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report a fully qualified struct update form" do
    """
    defmodule MyApp.Authorize do
      def touch(context) do
        %Trogon.Dispatcher.Context{context | response: :ok}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report a pattern match in a function head" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.Context

      def call(%Context{assigns: assigns} = context, next, _options) do
        next.(context, assigns)
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report a pattern match on the left side of =" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def take(result) do
        %DispatchOptions{actor: actor} = result
        actor
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report a pattern match in a case clause" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.Context

      def peek(context) do
        case context do
          %Context{kind: kind} -> kind
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report a struct literal unrelated to the configured modules" do
    """
    defmodule MyApp.Authorize do
      defmodule Options do
        @moduledoc false
        defstruct [:role]
      end

      def build do
        %Options{role: :admin}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "does not report inside the dispatcher's own namespace" do
    """
    defmodule Trogon.Dispatcher.Context do
      alias Trogon.Dispatcher.DispatchOptions

      def to_dispatch_options(context) do
        %DispatchOptions{actor: context.actor, assigns: context.assigns}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build do
        %DispatchOptions{}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction, hint: "See the dispatch guide.")
    |> assert_issue(fn issue -> assert issue.message =~ "See the dispatch guide." end)
  end

  test "accepts a custom dispatch options marker" do
    """
    defmodule MyApp.Authorize do
      def build do
        %MyApp.Options{}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction, dispatch_options_modules: [MyApp.Options])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Options" end)
  end

  test "accepts a custom context marker" do
    """
    defmodule MyApp.Authorize do
      def build do
        %MyApp.Ctx{}
      end
    end
    """
    |> to_source_file()
    |> run_check(StructConstruction, context_modules: [MyApp.Ctx])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Ctx" end)
  end
end
