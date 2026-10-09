defmodule Trogon.Credo.Check.Dispatcher.DispatchOptionsKeysTest do
  use Credo.Test.Case

  alias Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys

  test "does not report a map literal with known keys" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        DispatchOptions.new!(%{actor: actor, assigns: %{tenant: :acme}})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "reports an unknown key in a map literal" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        DispatchOptions.new!(%{actor: actor, private: %{}})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.check == DispatchOptionsKeys
      assert issue.category == DispatchOptionsKeys.category()
      assert issue.trigger == "new!"
      assert issue.message =~ ":private is not a known dispatch option"
    end)
  end

  test "reports a non-map assigns in a map literal" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build do
        DispatchOptions.new!(%{assigns: [tenant: :acme]})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue -> assert issue.message =~ "`assigns` must be a map" end)
  end

  for literal <- [~s("nope"), "42", ":nope", "nil", "{:actor, :someone}", "{:a, :b, :c}", "%MyApp.Options{}"] do
    test "reports a bare #{literal} literal passed to new/1" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build do
          DispatchOptions.new(#{unquote(literal)})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> assert_issue(fn issue ->
        assert issue.trigger == "new"
        assert issue.message =~ "must be a keyword list or a map"
      end)
    end
  end

  test "reports an unknown key" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        DispatchOptions.new!(actor: actor, bogus: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.trigger == "new!"
      assert issue.message =~ ":bogus"
      assert issue.message =~ "not a known dispatch option"
    end)
  end

  test "reports a repeated key" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(first, second) do
        DispatchOptions.new!(actor: first, actor: second)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.trigger == "new!"
      assert issue.message =~ ":actor"
      assert issue.message =~ "more than once"
    end)
  end

  test "reports a repeated key on the piped form" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(first, second) do
        [actor: first, actor: second] |> DispatchOptions.new!()
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.trigger == "new!"
      assert issue.message =~ "more than once"
    end)
  end

  test "reports assigns given as a keyword list instead of a map" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(tenant) do
        DispatchOptions.new!(assigns: [tenant: tenant])
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.trigger == "new!"
      assert issue.message =~ "`assigns` must be a map"
    end)
  end

  for literal <- [~s("nope"), "42", ":nope"] do
    test "reports assigns given as the bare literal #{literal}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build do
          DispatchOptions.new!(assigns: #{unquote(literal)})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> assert_issue(fn issue -> assert issue.message =~ "`assigns` must be a map" end)
    end
  end

  test "reports a non-atom key inside a literal assigns map" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(tenant) do
        DispatchOptions.new!(assigns: %{"tenant" => tenant})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue ->
      assert issue.trigger == "new!"
      assert issue.message =~ ~s("tenant")
      assert issue.message =~ "must be an atom"
    end)
  end

  test "reports a number key inside a literal assigns map" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(tenant) do
        DispatchOptions.new!(assigns: %{1 => tenant})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> assert_issue(fn issue -> assert issue.message =~ "assigns key 1 must be an atom" end)
  end

  test "does not report a variable or call key inside a literal assigns map" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(key, tenant) do
        DispatchOptions.new!(assigns: %{key => tenant, String.to_existing_atom("region") => :eu})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  for key <- [:message_id, :correlation_id, :causation_id] do
    test "reports a 2-tuple literal for #{key}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build(ref) do
          DispatchOptions.new!(#{unquote(key)}: {:ref, ref})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> assert_issue(fn issue ->
        assert issue.trigger == "new!"
        assert issue.message =~ "String.Chars"
      end)
    end

    test "reports a 3-tuple literal for #{key}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build(ref) do
          DispatchOptions.new!(#{unquote(key)}: {:ref, ref, :extra})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> assert_issue(fn issue -> assert issue.message =~ "String.Chars" end)
    end

    test "reports a map literal for #{key}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build do
          DispatchOptions.new!(#{unquote(key)}: %{value: 1})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> assert_issue(fn issue -> assert issue.message =~ "String.Chars" end)
    end

    test "does not report a struct literal for #{key}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build do
          DispatchOptions.new!(#{unquote(key)}: %MyApp.Ref{value: 1})
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> refute_issues()
    end

    test "does not report a string literal for #{key}" do
      """
      defmodule MyApp.Authorize do
        alias Trogon.Dispatcher.DispatchOptions

        def build do
          DispatchOptions.new!(#{unquote(key)}: "req-1")
        end
      end
      """
      |> to_source_file()
      |> run_check(DispatchOptionsKeys)
      |> refute_issues()
    end
  end

  test "does not report a dynamic argument" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(opts) do
        DispatchOptions.new!(opts)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report a list with a dynamic element" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(extra) do
        DispatchOptions.new!([{:actor, "alice"}, extra])
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report a dynamic assigns value" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(assigns) do
        DispatchOptions.new!(assigns: assigns)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report a valid call" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor, tenant) do
        DispatchOptions.new!(actor: actor, assigns: %{tenant: tenant})
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report a zero-arg call" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build do
        DispatchOptions.new!()
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report a call on an unrelated module" do
    """
    defmodule MyApp.Authorize do
      def build(actor) do
        MyApp.Options.new!(actor: actor, bogus: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "does not report inside the dispatcher's own namespace" do
    """
    defmodule Trogon.Dispatcher.TestSupport.Builder do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        DispatchOptions.new!(actor: actor, bogus: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys)
    |> refute_issues()
  end

  test "appends the hint to the message" do
    """
    defmodule MyApp.Authorize do
      alias Trogon.Dispatcher.DispatchOptions

      def build(actor) do
        DispatchOptions.new!(actor: actor, bogus: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys, hint: "See the dispatch guide.")
    |> assert_issue(fn issue -> assert issue.message =~ "See the dispatch guide." end)
  end

  test "accepts a custom dispatch options marker" do
    """
    defmodule MyApp.Authorize do
      def build(actor) do
        MyApp.Options.new!(actor: actor, bogus: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(DispatchOptionsKeys, dispatch_options_modules: [MyApp.Options])
    |> assert_issue(fn issue -> assert issue.trigger == "new!" end)
  end
end
