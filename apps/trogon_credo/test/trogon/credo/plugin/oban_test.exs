defmodule Trogon.Credo.Plugin.ObanTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Oban.ForbiddenDecorator
  alias Trogon.Credo.Check.Oban.WorkerName
  alias Trogon.Credo.Check.Oban.WorkerQueue
  alias Trogon.Credo.Plugin.Oban, as: ObanPlugin

  @source """
  defmodule MyApp.SendWelcomeEmail do
    use Oban.Worker
  end

  defmodule MyApp.SendReceipt do
    use MyApp.Worker
  end

  defmodule MyApp.Mailer do
    use Oban.Pro.Decorator
  end
  """

  test "enables its checks" do
    issues = run_credo(config([{ObanPlugin, []}]), [{"sample.ex", @source}])

    assert [
             %{check: WorkerName, trigger: "MyApp.SendWelcomeEmail"},
             %{check: WorkerQueue, trigger: "Oban.Worker"},
             %{check: ForbiddenDecorator}
           ] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{ObanPlugin, []}], "%{extra: []}", "ci"), [{"sample.ex", @source}], ["--config-name", "ci"])

    assert [WorkerName, WorkerQueue, ForbiddenDecorator] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 in [WorkerName, WorkerQueue, ForbiddenDecorator]))
  end

  test "forwards workers and suffix to the worker checks" do
    plugins = [{ObanPlugin, [workers: [MyApp.Worker], suffix: "Job"]}]
    issues = run_credo(config(plugins), [{"sample.ex", @source}])

    assert [
             %{
               check: WorkerName,
               trigger: "MyApp.SendReceipt",
               message: "Worker module `MyApp.SendReceipt` must end with `Job`." <> _
             },
             %{check: WorkerQueue, trigger: "MyApp.Worker"},
             %{check: ForbiddenDecorator}
           ] = issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [{Trogon.Credo.Check.Oban.WorkerName, false}]}"
    issues = run_credo(config([{ObanPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{check: WorkerQueue}, %{check: ForbiddenDecorator}] = issues
  end

  test "leaves out the checks named in except" do
    plugins = [{ObanPlugin, [except: [WorkerName, ForbiddenDecorator]]}]

    assert [%{check: WorkerQueue}] = run_credo(config(plugins), [{"sample.ex", @source}])
  end
end
