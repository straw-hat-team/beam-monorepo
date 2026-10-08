defmodule Trogon.Credo.Plugin.CommandedTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Commanded.AggregateApplyCall
  alias Trogon.Credo.Plugin.Commanded, as: CommandedPlugin

  @aggregate """
  defmodule Acme.Review.Aggregate do
    use Trogon.Commanded.Aggregate, identifier: :id
  end
  """

  @wrapped_aggregate """
  defmodule Acme.Order.Aggregate do
    use Acme.Aggregate
  end
  """

  @caller """
  defmodule Acme.Review.Replay do
    def run(aggregate, event) do
      Acme.Review.Aggregate.apply(aggregate, event)
      Acme.Order.Aggregate.apply(aggregate, event)
    end
  end
  """

  @sources [{"aggregate.ex", @aggregate}, {"wrapped_aggregate.ex", @wrapped_aggregate}, {"caller.ex", @caller}]

  test "enables its checks" do
    issues = run_credo(config([{CommandedPlugin, []}]), @sources)

    assert [%{check: AggregateApplyCall, trigger: "Acme.Review.Aggregate"}] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues = run_credo(config([{CommandedPlugin, []}], "%{enabled: []}", "ci"), @sources, ["--config-name", "ci"])

    assert [%{check: AggregateApplyCall}] = issues
  end

  test "forwards aggregate_modules to the check" do
    issues = run_credo(config([{CommandedPlugin, [aggregate_modules: [Acme.Aggregate]]}]), @sources)

    assert [%{check: AggregateApplyCall, trigger: "Acme.Order.Aggregate"}] = issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.Commanded.AggregateApplyCall, []}]}"

    assert [] == run_credo(config([{CommandedPlugin, []}], checks), @sources)
  end

  test "leaves out the checks named in except" do
    assert [] == run_credo(config([{CommandedPlugin, [except: [AggregateApplyCall]]}]), @sources)
  end
end
