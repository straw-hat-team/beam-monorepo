defmodule Trogon.Credo.Plugin.DefaultTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.ExUnit.ApplicationEnvMutation
  alias Trogon.Credo.Check.Readability.OneModulePerFile
  alias Trogon.Credo.Check.Warning.RaiseString
  alias Trogon.Credo.Check.Warning.SystemEnvRead
  alias Trogon.Credo.Plugin.Default, as: DefaultPlugin
  alias Trogon.Credo.Plugin.ExUnit, as: ExUnitPlugin

  @source """
  defmodule Sample do
    def rate do
      System.get_env("TAX_RATE")
    end
  end
  """

  @env_mutation_source """
  defmodule SampleTest do
    def setup_env do
      Application.put_env(:sample, :key, 1)
    end
  end
  """

  @raise_source """
  defmodule Raiser do
    def run do
      raise "boom"
    end
  end
  """

  @two_modules_source """
  defmodule Outer do
    defmodule Inner do
    end
  end
  """

  @all_sources [
    {"sample.ex", @source},
    {"sample_test.exs", @env_mutation_source},
    {"raiser.ex", @raise_source},
    {"outer.ex", @two_modules_source}
  ]

  defp checks_of(issues), do: issues |> Enum.map(& &1.check) |> Enum.sort()

  test "enables each of the four checks with its defaults" do
    issues = run_credo(config([{DefaultPlugin, []}]), @all_sources)

    assert checks_of(issues) ==
             Enum.sort([SystemEnvRead, ApplicationEnvMutation, RaiseString, OneModulePerFile])
  end

  test "enables its checks when the project lists checks with enabled:" do
    issues = run_credo(config([{DefaultPlugin, []}]), [{"sample.ex", @source}])

    assert [%{check: SystemEnvRead, trigger: "System.get_env"}] = issues
  end

  test "enables its checks when the project lists checks with extra:" do
    issues = run_credo(config([{DefaultPlugin, []}], "%{extra: []}"), [{"sample.ex", @source}])

    assert [SystemEnvRead] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == SystemEnvRead))
  end

  test "enables its checks when the project lists checks as a plain list" do
    issues = run_credo(config([{DefaultPlugin, []}], "[]"), [{"sample.ex", @source}])

    assert [SystemEnvRead] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == SystemEnvRead))
  end

  test "keeps the project's own extra: entry for a check it enables" do
    checks =
      "%{extra: [{Trogon.Credo.Check.Warning.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{DefaultPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == SystemEnvRead))
    assert message =~ "Read it through Acme.Config."
  end

  test "keeps the project's own plain list entry for a check it enables" do
    checks =
      "[{Trogon.Credo.Check.Warning.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]"

    issues = run_credo(config([{DefaultPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == SystemEnvRead))
    assert message =~ "Read it through Acme.Config."
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{DefaultPlugin, []}], "%{enabled: []}", "ci"), [{"sample.ex", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: SystemEnvRead}] = issues
  end

  test "keeps the project's own entry for a check it enables" do
    checks =
      "%{enabled: [{Trogon.Credo.Check.Warning.SystemEnvRead, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{DefaultPlugin, []}], checks), [{"sample.ex", @source}])

    assert [%{message: message}] = issues
    assert message =~ "Read it through Acme.Config."
  end

  test "leaves a check disabled when the project disables it" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.Warning.SystemEnvRead, []}]}"

    assert [] == run_credo(config([{DefaultPlugin, []}], checks), [{"sample.ex", @source}])
  end

  test "leaves out the checks named in except" do
    for check <- [SystemEnvRead, ApplicationEnvMutation, RaiseString, OneModulePerFile] do
      issues = run_credo(config([{DefaultPlugin, [except: [check]]}]), @all_sources)

      assert length(issues) == 3
      refute check in checks_of(issues)
    end
  end

  test "a project's own entry overrides params, such as allowed_files" do
    checks =
      "%{enabled: [{Trogon.Credo.Check.Warning.SystemEnvRead, [allowed_files: [{\"sample.ex\", \"A sample that reads the environment.\"}]]}]}"

    issues = run_credo(config([{DefaultPlugin, []}], checks), [{"sample.ex", @source}])

    assert [] == issues
  end

  test "using it with the ExUnit plugin reports the check once" do
    issues =
      run_credo(config([{DefaultPlugin, []}, {ExUnitPlugin, []}]), [{"sample_test.exs", @env_mutation_source}])

    assert [ApplicationEnvMutation] = checks_of(issues)

    issues =
      run_credo(config([{ExUnitPlugin, []}, {DefaultPlugin, []}]), [{"sample_test.exs", @env_mutation_source}])

    assert [ApplicationEnvMutation] = checks_of(issues)
  end

  test "honors a disable comment naming the dedicated check" do
    source = """
    defmodule Sample do
      def rate do
        # credo:disable-for-next-line Trogon.Credo.Check.Warning.SystemEnvRead
        System.get_env("TAX_RATE")
      end
    end
    """

    assert [] == run_credo(config([{DefaultPlugin, []}]), [{"sample.ex", source}])
  end

  test "raises when except names a check the plugin does not enable" do
    assert_raise ArgumentError, ~r/invalid except/, fn ->
      run_credo(config([{DefaultPlugin, [except: [Trogon.Credo.Check.Warning.ForbiddenUse]]}]), [
        {"sample.ex", @source}
      ])
    end
  end
end
