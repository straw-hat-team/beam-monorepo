defmodule Trogon.Credo.Plugin.EctoTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Ecto.RepoTransact
  alias Trogon.Credo.Plugin.Ecto, as: EctoPlugin

  @source """
  defmodule Sample do
    def run do
      MyApp.Repo.transact(fn -> {:ok, :done} end)
      MyApp.ReadOnlyRepo.transact(fn -> {:ok, :done} end)
    end
  end
  """

  test "enables its checks when the project lists checks with enabled:" do
    issues = run_credo(config([{EctoPlugin, []}]), [{"sample.ex", @source}])

    assert [%{check: RepoTransact, trigger: "MyApp.Repo.transact"}] = issues
  end

  test "enables its checks when the project lists checks with extra:" do
    issues = run_credo(config([{EctoPlugin, []}], "%{extra: []}"), [{"sample.ex", @source}])

    assert [RepoTransact] = issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == RepoTransact))
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{EctoPlugin, []}], "%{enabled: []}", "ci"), [{"sample.ex", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: RepoTransact}] = issues
  end

  test "forwards repos to the check" do
    issues = run_credo(config([{EctoPlugin, [repos: [MyApp.ReadOnlyRepo]]}]), [{"sample.ex", @source}])

    assert [%{trigger: "MyApp.ReadOnlyRepo.transact"}] = issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks = "%{enabled: [{Trogon.Credo.Check.Ecto.RepoTransact, [repos: [MyApp.ReadOnlyRepo]]}]}"
    issues = run_credo(config([{EctoPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{trigger: "MyApp.ReadOnlyRepo.transact"}] = issues
  end

  test "leaves a check disabled when the project disables it" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.Ecto.RepoTransact, []}]}"

    assert [] == run_credo(config([{EctoPlugin, []}], checks), [{"sample.ex", @source}])
  end

  test "leaves out the checks named in except" do
    assert [] == run_credo(config([{EctoPlugin, [except: [RepoTransact]]}]), [{"sample.ex", @source}])
  end

  test "honors a disable comment naming the dedicated check" do
    source = """
    defmodule Sample do
      def run do
        # credo:disable-for-next-line Trogon.Credo.Check.Ecto.RepoTransact
        MyApp.Repo.transact(fn -> {:ok, :done} end)
      end
    end
    """

    assert [] == run_credo(config([{EctoPlugin, []}]), [{"sample.ex", source}])
  end

  test "raises when except names a check the plugin does not enable" do
    assert_raise ArgumentError, ~r/invalid except/, fn ->
      run_credo(config([{EctoPlugin, [except: [Trogon.Credo.Check.Warning.ForbiddenUse]]}]), [
        {"sample.ex", @source}
      ])
    end
  end
end
