defmodule Trogon.Credo.Plugin.OpenTelemetryTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.OpenTelemetry.TaskPropagation
  alias Trogon.Credo.Plugin.OpenTelemetry, as: OpenTelemetryPlugin

  @source """
  defmodule Sample do
    def run do
      Task.async(fn -> :done end)
    end
  end
  """

  test "enables its checks" do
    issues = run_credo(config([{OpenTelemetryPlugin, []}]), [{"sample.ex", @source}])

    assert [%{check: TaskPropagation, message: "Call `OpentelemetryProcessPropagator.Task` instead" <> _}] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{OpenTelemetryPlugin, []}], "%{enabled: []}", "ci"), [{"sample.ex", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: TaskPropagation}] = issues
  end

  test "forwards task to the check" do
    issues = run_credo(config([{OpenTelemetryPlugin, [task: MyApp.Task]}]), [{"sample.ex", @source}])

    assert [%{check: TaskPropagation, message: "Call `MyApp.Task` instead of `Task`" <> _}] = issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [{Trogon.Credo.Check.OpenTelemetry.TaskPropagation, false}]}"

    assert [] == run_credo(config([{OpenTelemetryPlugin, []}], checks), [{"sample.ex", @source}])
  end

  test "leaves out the checks named in except" do
    plugins = [{OpenTelemetryPlugin, [except: [TaskPropagation]]}]

    assert [] == run_credo(config(plugins), [{"sample.ex", @source}])
  end
end
