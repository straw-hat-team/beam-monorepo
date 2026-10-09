defmodule Trogon.Credo.Plugin.CommandedTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Commanded.AggregateApplyCall
  alias Trogon.Credo.Check.Commanded.DeterministicCommand
  alias Trogon.Credo.Check.Commanded.ErrorOwnership
  alias Trogon.Credo.Check.Commanded.SwappableNonDeterminism
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

  @command_handler """
  defmodule Acme.Review.CommandHandler do
    use Trogon.Commanded.CommandHandler, aggregate: Acme.Review.Aggregate

    def handle(aggregate, command) do
      DateTime.utc_now()
    end
  end
  """

  @wrapped_command_handler """
  defmodule Acme.Order.CommandHandler do
    use Acme.CommandHandler

    def handle(aggregate, command) do
      DateTime.utc_now()
    end
  end
  """

  @event_handler """
  defmodule Acme.Review.EventHandler do
    use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

    def handle(event, _metadata) do
      Ecto.UUID.generate()
    end
  end
  """

  @worker """
  defmodule Acme.Review.Worker do
    use Oban.Pro.Worker

    def process(_job) do
      Ecto.UUID.generate()
    end
  end
  """

  @foreign_error_raise """
  defmodule Acme.Web.ReviewController do
    def create(params) do
      raise Acme.Review.Domain.NotFoundError
    end
  end
  """

  @wrapped_aggregate_with_call """
  defmodule Acme.Order.Aggregate do
    use Acme.Aggregate

    def execute(aggregate, command) do
      DateTime.utc_now()
    end
  end
  """

  test "enables its checks" do
    issues = run_credo(config([{CommandedPlugin, []}]), @sources)

    assert [%{check: AggregateApplyCall, trigger: "Acme.Review.Aggregate"}] = issues
  end

  test "enables its checks under a config selected with --config-name" do
    issues = run_credo(config([{CommandedPlugin, []}], "%{enabled: []}", "ci"), @sources, ["--config-name", "ci"])

    assert [%{check: AggregateApplyCall}] = issues
  end

  test "forwards aggregate_modules to AggregateApplyCall" do
    issues = run_credo(config([{CommandedPlugin, [aggregate_modules: [Acme.Aggregate]]}]), @sources)

    assert [%{check: AggregateApplyCall, trigger: "Acme.Order.Aggregate"}] = issues
  end

  test "forwards aggregate_modules to DeterministicCommand" do
    issues =
      run_credo(config([{CommandedPlugin, [aggregate_modules: [Acme.Aggregate]]}]), [
        {"wrapped_aggregate.ex", @wrapped_aggregate_with_call}
      ])

    assert [%{check: DeterministicCommand, trigger: "DateTime.utc_now"}] = issues
  end

  test "forwards command_handler_modules to DeterministicCommand" do
    issues =
      run_credo(config([{CommandedPlugin, [command_handler_modules: [Acme.CommandHandler]]}]), [
        {"command_handler.ex", @wrapped_command_handler}
      ])

    assert [%{check: DeterministicCommand, trigger: "DateTime.utc_now"}] = issues
  end

  test "forwards command_modules and event_modules to DeterministicCommand" do
    sources = [
      {"command.ex",
       "defmodule Acme.Order.Command.Place do\n  use Acme.Command\n  def new, do: DateTime.utc_now()\nend\n"},
      {"event.ex", "defmodule Acme.Order.Event.Placed do\n  use Acme.Event\n  def new, do: Ecto.UUID.generate()\nend\n"}
    ]

    issues =
      run_credo(config([{CommandedPlugin, [command_modules: [Acme.Command], event_modules: [Acme.Event]]}]), sources)

    assert [%{check: DeterministicCommand}, %{check: DeterministicCommand}] = issues
    assert issues |> Enum.map(& &1.trigger) |> Enum.sort() == ["DateTime.utc_now", "Ecto.UUID.generate"]
  end

  test "forwards processor_modules to SwappableNonDeterminism" do
    issues = run_credo(config([{CommandedPlugin, [processor_modules: [Oban.Pro.Worker]]}]), [{"worker.ex", @worker}])

    assert [%{check: SwappableNonDeterminism, trigger: "Ecto.UUID.generate"}] = issues
  end

  test "enables DeterministicCommand against the default aggregate and command handler modules" do
    issues = run_credo(config([{CommandedPlugin, []}]), [{"command_handler.ex", @command_handler}])

    assert [%{check: DeterministicCommand, trigger: "DateTime.utc_now"}] = issues
  end

  test "enables SwappableNonDeterminism against the default processor modules" do
    issues = run_credo(config([{CommandedPlugin, []}]), [{"event_handler.ex", @event_handler}])

    assert [%{check: SwappableNonDeterminism, trigger: "Ecto.UUID.generate"}] = issues
  end

  test "enables ErrorOwnership against the default error pattern" do
    issues = run_credo(config([{CommandedPlugin, []}]), [{"controller.ex", @foreign_error_raise}])

    assert [%{check: ErrorOwnership, trigger: "Acme.Review.Domain.NotFoundError"}] = issues
  end

  test "forwards shared to ErrorOwnership" do
    issues =
      run_credo(config([{CommandedPlugin, [shared: ["Acme.Review"]]}]), [{"controller.ex", @foreign_error_raise}])

    assert [] == issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.Commanded.AggregateApplyCall, []}]}"

    assert [] == run_credo(config([{CommandedPlugin, []}], checks), @sources)
  end

  test "leaves out the checks named in except" do
    except = [AggregateApplyCall, DeterministicCommand, SwappableNonDeterminism, ErrorOwnership]

    assert [] ==
             run_credo(
               config([{CommandedPlugin, [except: except]}]),
               @sources ++ [{"command_handler.ex", @command_handler}, {"event_handler.ex", @event_handler}]
             )
  end

  test "honors a disable comment naming DeterministicCommand" do
    source = """
    defmodule Acme.Review.CommandHandler do
      use Trogon.Commanded.CommandHandler, aggregate: Acme.Review.Aggregate

      def handle(aggregate, command) do
        # credo:disable-for-next-line Trogon.Credo.Check.Commanded.DeterministicCommand
        DateTime.utc_now()
      end
    end
    """

    assert [] == run_credo(config([{CommandedPlugin, []}]), [{"command_handler.ex", source}])
  end

  test "honors a disable comment naming SwappableNonDeterminism" do
    source = """
    defmodule Acme.Review.EventHandler do
      use Commanded.Event.Handler, application: Acme.App, name: __MODULE__

      def handle(event, _metadata) do
        # credo:disable-for-next-line Trogon.Credo.Check.Commanded.SwappableNonDeterminism
        Ecto.UUID.generate()
      end
    end
    """

    assert [] == run_credo(config([{CommandedPlugin, []}]), [{"event_handler.ex", source}])
  end

  test "honors a disable comment naming ErrorOwnership" do
    source = """
    defmodule Acme.Web.ReviewController do
      def create(params) do
        # credo:disable-for-next-line Trogon.Credo.Check.Commanded.ErrorOwnership
        raise Acme.Review.Domain.NotFoundError
      end
    end
    """

    assert [] == run_credo(config([{CommandedPlugin, []}]), [{"controller.ex", source}])
  end

  test "raises when except names a check the plugin does not enable" do
    assert_raise ArgumentError, ~r/invalid except/, fn ->
      run_credo(config([{CommandedPlugin, [except: [Trogon.Credo.Check.Warning.ForbiddenUse]]}]), @sources)
    end
  end
end
