defmodule Trogon.Credo.Check.Dispatcher.PrivateOwnershipTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Dispatcher.PrivateOwnership

  test "reports a piped put_private naming another module as the owner" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> assert_issue(fn issue ->
      assert issue.check == PrivateOwnership
      assert issue.category == PrivateOwnership.category()
      assert issue.trigger == "MyApp.OtherMiddleware"
      assert issue.message =~ "__MODULE__"
    end)
  end

  test "reports an unpiped put_private naming another module as the owner" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        updated = Context.put_private(context, MyApp.OtherMiddleware, :checked)
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.OtherMiddleware" end)
  end

  test "reports a fully qualified owner naming another module" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        context |> Trogon.Dispatcher.Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.OtherMiddleware" end)
  end

  test "does not report put_private naming __MODULE__" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(__MODULE__, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report put_private naming the enclosing module by its own name" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(MyApp.Authorize, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report get_private naming another module" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        tenant = Context.get_private(context, MyApp.OtherMiddleware)
        next.(context, tenant)
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report a dynamic owner" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, owner) do
        context |> Context.put_private(owner, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report put_private outside a middleware" do
    """
    defmodule MyApp.NotAMiddleware do
      alias Trogon.Dispatcher.Context

      def touch(context) do
        context |> Context.put_private(MyApp.OtherMiddleware, :checked)
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report put_private on an unrelated module" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def touch(store) do
        MyApp.Store.put_private(store, MyApp.OtherMiddleware, :checked)
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "does not report inside the dispatcher's own namespace" do
    """
    defmodule Trogon.Dispatcher.TestSupport.Stamp do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(Trogon.Dispatcher.TestSupport.OtherOne, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership, hint: "See the middleware guide.")
    |> assert_issue(fn issue -> assert issue.message =~ "See the middleware guide." end)
  end

  test "accepts a custom middleware marker" do
    """
    defmodule MyApp.Authorize do
      @behaviour MyApp.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership, middleware_modules: [MyApp.Middleware])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.OtherMiddleware" end)
  end

  test "accepts a custom context marker" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias MyApp.Ctx

      def call(context, next, _options) do
        context |> Ctx.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(PrivateOwnership, context_modules: [MyApp.Ctx])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.OtherMiddleware" end)
  end
end
