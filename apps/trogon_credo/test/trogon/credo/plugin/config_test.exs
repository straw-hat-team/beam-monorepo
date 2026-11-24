defmodule Trogon.Credo.Plugin.ConfigTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.Config.SystemEnvRead
  alias Trogon.Credo.Plugin.Config, as: ConfigPlugin

  @source """
  defmodule Sample do
    def rate do
      System.get_env("TAX_RATE")
    end
  end
  """

  test "enables its checks when the project lists checks with enabled:" do
    issues = run_credo(config([{ConfigPlugin, []}]), [{"sample.ex", @source}])

    assert [%{check: SystemEnvRead, trigger: "System.get_env"}] = issues
  end

  test "enables its checks when the project lists checks with extra:" do
    issues = run_credo(config([{ConfigPlugin, []}], "%{extra: []}"), [{"sample.ex", @source}])

    assert [SystemEnvRead] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == SystemEnvRead))
  end

  test "enables its checks when the project lists checks as a plain list" do
    issues = run_credo(config([{ConfigPlugin, []}], "[]"), [{"sample.ex", @source}])

    assert [SystemEnvRead] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == SystemEnvRead))
  end

  test "keeps the project's own extra: entry for a check it enables" do
    checks =
      "%{extra: [{Trogon.Credo.Check.Config.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{ConfigPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == SystemEnvRead))
    assert message =~ "Read it through Acme.Config."
  end

  test "keeps the project's own plain list entry for a check it enables" do
    checks =
      "[{Trogon.Credo.Check.Config.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]"

    issues = run_credo(config([{ConfigPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == SystemEnvRead))
    assert message =~ "Read it through Acme.Config."
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{ConfigPlugin, []}], "%{enabled: []}", "ci"), [{"sample.ex", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: SystemEnvRead}] = issues
  end

  test "forwards allowed_files to the check" do
    assert [] == run_credo(config([{ConfigPlugin, [allowed_files: ["sample.ex"]]}]), [{"sample.ex", @source}])
  end

  test "forwards calls to the check" do
    assert [] == run_credo(config([{ConfigPlugin, [calls: [{Acme.Env, :fetch}]]}]), [{"sample.ex", @source}])
  end

  test "forwards hint to the check" do
    issues =
      run_credo(config([{ConfigPlugin, [hint: "Read it through Acme.Config."]}]), [{"sample.ex", @source}])

    assert [%{message: message}] = issues
    assert message =~ "Read it through Acme.Config."
  end

  test "keeps the project's own entry for a check it enables" do
    checks =
      "%{enabled: [{Trogon.Credo.Check.Config.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{ConfigPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = issues
    assert message =~ "Read it through Acme.Config."
  end

  test "leaves a check disabled when the project disables it" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.Config.SystemEnvRead, []}]}"

    assert [] == run_credo(config([{ConfigPlugin, []}], checks), [{"sample.ex", @source}])
  end

  test "leaves out the checks named in except" do
    assert [] ==
             run_credo(config([{ConfigPlugin, [except: [SystemEnvRead]]}]), [
               {"sample.ex", @source}
             ])
  end

  test "honors a disable comment naming the dedicated check" do
    source = """
    defmodule Sample do
      def rate do
        # credo:disable-for-next-line Trogon.Credo.Check.Config.SystemEnvRead
        System.get_env("TAX_RATE")
      end
    end
    """

    assert [] == run_credo(config([{ConfigPlugin, []}]), [{"sample.ex", source}])
  end

  test "raises when except names a check the plugin does not enable" do
    assert_raise ArgumentError, ~r/invalid except/, fn ->
      run_credo(config([{ConfigPlugin, [except: [Trogon.Credo.Check.Warning.ForbiddenUse]]}]), [
        {"sample.ex", @source}
      ])
    end
  end
end
