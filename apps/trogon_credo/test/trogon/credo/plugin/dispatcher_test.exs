defmodule Trogon.Credo.Plugin.DispatcherTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Dispatcher.ContextMutation
  alias Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys
  alias Trogon.Credo.Check.Dispatcher.PrivateOwnership
  alias Trogon.Credo.Check.Dispatcher.StructConstruction
  alias Trogon.Credo.Plugin.Dispatcher, as: DispatcherPlugin

  @context_mutation_source """
  defmodule MyApp.Authorize do
    @behaviour Trogon.Dispatcher.Middleware

    def call(context, next, _options) do
      %{context | response: :ok} |> next.()
    end
  end
  """

  @struct_construction_source """
  defmodule MyApp.Authorize do
    alias Trogon.Dispatcher.DispatchOptions

    def build(actor) do
      %DispatchOptions{actor: actor}
    end
  end
  """

  @private_ownership_source """
  defmodule MyApp.Authorize do
    @behaviour Trogon.Dispatcher.Middleware
    alias Trogon.Dispatcher.Context

    def call(context, next, _options) do
      context |> Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
    end
  end
  """

  @dispatch_options_keys_source """
  defmodule MyApp.Authorize do
    alias Trogon.Dispatcher.DispatchOptions

    def build(actor) do
      DispatchOptions.new!(actor: actor, bogus: true)
    end
  end
  """

  test "enables its checks" do
    issues = run_credo(config([{DispatcherPlugin, []}]), [{"sample.ex", @context_mutation_source}])

    assert [%{check: ContextMutation, trigger: "|"}] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{DispatcherPlugin, []}], "%{extra: []}", "ci"), [{"sample.ex", @context_mutation_source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: ContextMutation, trigger: "|"}] = issues
  end

  test "enables StructConstruction" do
    issues = run_credo(config([{DispatcherPlugin, []}]), [{"sample.ex", @struct_construction_source}])

    assert [%{check: StructConstruction, trigger: "DispatchOptions"}] = issues
  end

  test "enables PrivateOwnership" do
    issues = run_credo(config([{DispatcherPlugin, []}]), [{"sample.ex", @private_ownership_source}])

    assert [%{check: PrivateOwnership, trigger: "MyApp.OtherMiddleware"}] = issues
  end

  test "enables DispatchOptionsKeys" do
    issues = run_credo(config([{DispatcherPlugin, []}]), [{"sample.ex", @dispatch_options_keys_source}])

    assert [%{check: DispatchOptionsKeys, trigger: "new!"}] = issues
  end

  test "forwards middleware_modules, handler_modules, context_modules and except_in to ContextMutation" do
    source = """
    defmodule MyApp.Authorize do
      @behaviour MyApp.Middleware

      def call(context, next, _options) do
        %{context | response: :ok} |> next.()
      end
    end
    """

    plugins = [
      {DispatcherPlugin,
       [middleware_modules: [MyApp.Middleware], handler_modules: [], context_modules: [], except_in: []]}
    ]

    assert [%{check: ContextMutation, trigger: "|"}] =
             run_credo(config(plugins), [{"sample.ex", source}])
  end

  test "forwards dispatch_options_modules and except_in to StructConstruction" do
    source = """
    defmodule MyApp.Authorize do
      alias MyApp.Options

      def build(actor) do
        %Options{actor: actor}
      end
    end
    """

    plugins = [{DispatcherPlugin, [dispatch_options_modules: [MyApp.Options], except_in: []]}]

    assert [%{check: StructConstruction, trigger: "Options"}] =
             run_credo(config(plugins), [{"sample.ex", source}])
  end

  test "forwards middleware_modules to PrivateOwnership" do
    source = """
    defmodule MyApp.Authorize do
      @behaviour MyApp.Middleware
      alias Trogon.Dispatcher.Context

      def call(context, next, _options) do
        context |> Context.put_private(MyApp.OtherMiddleware, :checked) |> next.()
      end
    end
    """

    plugins = [{DispatcherPlugin, [middleware_modules: [MyApp.Middleware]]}]

    assert [%{check: PrivateOwnership, trigger: "MyApp.OtherMiddleware"}] =
             run_credo(config(plugins), [{"sample.ex", source}])
  end

  test "forwards dispatch_options_modules to DispatchOptionsKeys" do
    source = """
    defmodule MyApp.Authorize do
      alias MyApp.Options

      def build(actor) do
        Options.new!(actor: actor, bogus: true)
      end
    end
    """

    plugins = [{DispatcherPlugin, [dispatch_options_modules: [MyApp.Options]]}]

    assert [%{check: DispatchOptionsKeys, trigger: "new!"}] =
             run_credo(config(plugins), [{"sample.ex", source}])
  end

  test "forwards hint to every check" do
    plugins = [{DispatcherPlugin, [hint: "See the dispatch guide."]}]

    [issue] = run_credo(config(plugins), [{"sample.ex", @context_mutation_source}])
    assert issue.message =~ "See the dispatch guide."
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [{Trogon.Credo.Check.Dispatcher.ContextMutation, false}]}"

    assert [] = run_credo(config([{DispatcherPlugin, []}], checks), [{"sample.ex", @context_mutation_source}])
  end

  test "leaves out the checks named in except" do
    plugins = [
      {DispatcherPlugin, [except: [ContextMutation, StructConstruction, PrivateOwnership, DispatchOptionsKeys]]}
    ]

    sources = [
      {"context_mutation.ex", @context_mutation_source},
      {"struct_construction.ex", @struct_construction_source},
      {"private_ownership.ex", @private_ownership_source},
      {"dispatch_options_keys.ex", @dispatch_options_keys_source}
    ]

    assert [] = run_credo(config(plugins), sources)
  end
end
