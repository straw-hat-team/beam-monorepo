defmodule Trogon.Credo.Check.Dispatcher.ContextMutationTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Dispatcher.ContextMutation

  for field <- [:message, :kind, :dispatcher, :registered_by] do
    test "reports a map update of #{field} inside a middleware" do
      """
      defmodule MyApp.Authorize do
        @behaviour Trogon.Dispatcher.Middleware

        def call(context, next, _options) do
          %{context | #{unquote(field)}: :changed} |> next.()
        end
      end
      """
      |> to_source_file()
      |> run_check(ContextMutation)
      |> assert_issue(fn issue ->
        assert issue.check == ContextMutation
        assert issue.category == ContextMutation.category()
        assert issue.trigger == "|"
        assert issue.message =~ "is set by the dispatch and never changed"
      end)
    end
  end

  test "reports a map update of assigns inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        %{context | assigns: Map.put(context.assigns, :tenant, "acme")} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "|"
      assert issue.message =~ "Trogon.Dispatcher.Context.assign/3"
      assert issue.message =~ "Trogon.Dispatcher.Context.merge_assigns/2"
    end)
  end

  test "reports a map update of private inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        %{context | private: Map.put(context.private, __MODULE__, :checked)} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "|"
      assert issue.message =~ "Trogon.Dispatcher.Context.put_private/3"
    end)
  end

  test "reports a map update of response inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, _next, _options) do
        %{context | response: {:error, :unauthorized}}
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue ->
      assert issue.trigger == "|"
      assert issue.message =~ "Trogon.Dispatcher.Context.put_response/2"
    end)
  end

  test "reports a map update inside a handler" do
    """
    defmodule MyApp.RegisterUser do
      @behaviour Trogon.Dispatcher.Handler

      def handle_message(message, context) do
        updated = %{context | response: :ok}
        {:ok, updated}
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "|" end)
  end

  test "reports the struct update form named Context" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        %Context{context | private: %{}} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "|" end)
  end

  test "reports the struct update form fully qualified" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        %Trogon.Dispatcher.Context{context | assigns: %{}} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "|" end)
  end

  test "does not report a struct update whose name is not a configured context module" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      defmodule Unrelated do
        @moduledoc false
        defstruct [:assigns, :kind]
      end

      def call(context, next, _options) do
        unrelated = %Unrelated{assigns: nil, kind: nil}
        %Unrelated{unrelated | assigns: %{}, kind: :other}
        next.(context)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "reports Map.put/3 on a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = Map.put(context, :response, :ok)
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "put" end)
  end

  test "reports Map.replace!/3 on a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = Map.replace!(context, :private, %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "replace!" end)
  end

  test "reports struct!/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = struct!(context, assigns: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct!" end)
  end

  test "does not report struct construction of another module's struct inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        next.(struct!(MyApp.Events.Rejected, message: context.message))
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "does not report struct construction of the own module's struct inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        next.(struct(__MODULE__, message: context.message))
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "does not report struct construction of an atom module name inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        next.(Kernel.struct!(:"Elixir.MyApp.Events.Rejected", message: context.message))
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "reports struct!/2 naming the context module inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        next.(struct!(Context, assigns: %{}))
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct!" end)
  end

  test "reports Kernel.struct!/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = Kernel.struct!(context, private: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct!" end)
  end

  test "reports a piped Map.put/3 on a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> Map.put(:response, :ok)
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "put" end)
  end

  test "reports a piped Map.replace!/3 on a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> Map.replace!(:private, %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "replace!" end)
  end

  test "reports a piped struct!/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> struct!(assigns: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct!" end)
  end

  test "reports a piped Kernel.struct!/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> Kernel.struct!(private: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct!" end)
  end

  test "reports struct/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = struct(context, assigns: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct" end)
  end

  test "reports Kernel.struct/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = Kernel.struct(context, private: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct" end)
  end

  test "reports a piped struct/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> struct(response: :ok)
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct" end)
  end

  test "reports a piped Kernel.struct/2 naming a restricted field inside a middleware" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        updated = context |> Kernel.struct(assigns: %{})
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issue(fn issue -> assert issue.trigger == "struct" end)
  end

  test "does not report Map.put/3 whose key is not a literal atom" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, field: field, value: value) do
        updated = Map.put(context, field, value)
        next.(updated)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "reports every restricted field a single update names" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        %{context | assigns: %{}, private: %{}} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "does not report a module that implements neither behaviour" do
    """
    defmodule MyApp.PlainStruct do
      defstruct [:assigns]

      def build(context) do
        %{context | assigns: %{}}
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "does not report a middleware that only uses the Context writer functions" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context
        |> Context.assign(:tenant, "acme")
        |> Context.put_private(__MODULE__, :checked)
        |> next.()
        |> Context.put_response({:error, :unauthorized})
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "does not report a plain struct update unrelated to the context" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      defmodule Options do
        @moduledoc false
        defstruct [:role]
      end

      def init(opts), do: %Options{role: Keyword.fetch!(opts, :role)}

      def call(context, next, %Options{} = options) do
        %{options | role: :admin}
        next.(context)
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "does not report inside the dispatcher's own namespace" do
    """
    defmodule Trogon.Dispatcher.TestSupport.OverwriteField do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, _next, _options) do
        %{context | response: :changed}
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Authorize do
      @behaviour Trogon.Dispatcher.Middleware

      def call(context, next, _options) do
        %{context | response: :ok} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation, hint: "See the middleware guide.")
    |> assert_issue(fn issue -> assert issue.message =~ "See the middleware guide." end)
  end

  test "accepts a custom middleware marker" do
    """
    defmodule MyApp.Authorize do
      @behaviour MyApp.Middleware

      def call(context, next, _options) do
        %{context | response: :ok} |> next.()
      end
    end
    """
    |> to_source_file()
    |> run_check(ContextMutation, middleware_modules: [MyApp.Middleware])
    |> assert_issue(fn issue -> assert issue.trigger == "|" end)
  end
end
