defmodule Trogon.Credo.Plugin.DispatcherTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Dispatcher.ContextMutation
  alias Trogon.Credo.Plugin.Dispatcher, as: DispatcherPlugin

  @source """
  defmodule MyApp.Authorize do
    @behaviour Trogon.Dispatcher.Middleware

    def call(context, next, _options) do
      %{context | response: :ok} |> next.()
    end
  end
  """

  test "enables its checks" do
    issues = run_credo(config([{DispatcherPlugin, []}]), [{"sample.ex", @source}])

    assert [%{check: ContextMutation, trigger: "|"}] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{DispatcherPlugin, []}], "%{extra: []}", "ci"), [{"sample.ex", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: ContextMutation, trigger: "|"}] = issues
  end

  test "forwards middleware_modules, handler_modules, context_modules and except_in to the check" do
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

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [{Trogon.Credo.Check.Dispatcher.ContextMutation, false}]}"

    assert [] = run_credo(config([{DispatcherPlugin, []}], checks), [{"sample.ex", @source}])
  end

  test "leaves out the checks named in except" do
    plugins = [{DispatcherPlugin, [except: [ContextMutation]]}]

    assert [] = run_credo(config(plugins), [{"sample.ex", @source}])
  end
end
