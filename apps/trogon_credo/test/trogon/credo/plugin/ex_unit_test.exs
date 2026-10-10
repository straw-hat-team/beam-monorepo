defmodule Trogon.Credo.Plugin.ExUnitTest do
  use Trogon.Credo.PluginCase, async: false

  alias Trogon.Credo.Check.ExUnit.ApplicationEnvMutation
  alias Trogon.Credo.Plugin.ExUnit, as: ExUnitPlugin

  @source """
  defmodule SampleTest do
    test "charges the configured tax rate" do
      Application.put_env(:acme, :tax_rate, 0.07)
    end
  end
  """

  test "enables its checks when the project lists checks with enabled:" do
    issues = run_credo(config([{ExUnitPlugin, []}]), [{"sample_test.exs", @source}])

    assert [%{check: ApplicationEnvMutation, trigger: "Application.put_env"}] = issues
  end

  test "enables its checks when the project lists checks with extra:" do
    issues = run_credo(config([{ExUnitPlugin, []}], "%{extra: []}"), [{"sample_test.exs", @source}])

    assert [ApplicationEnvMutation] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == ApplicationEnvMutation))
  end

  test "enables its checks when the project lists checks as a plain list" do
    issues = run_credo(config([{ExUnitPlugin, []}], "[]"), [{"sample_test.exs", @source}])

    assert [ApplicationEnvMutation] =
             issues |> Enum.map(& &1.check) |> Enum.filter(&(&1 == ApplicationEnvMutation))
  end

  test "keeps the project's own extra: entry for a check it enables" do
    checks =
      "%{extra: [{Trogon.Credo.Check.ExUnit.ApplicationEnvMutation, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{ExUnitPlugin, []}], checks), [{"sample_test.exs", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == ApplicationEnvMutation))
    assert message =~ "Read it through Acme.Config."
  end

  test "keeps the project's own plain list entry for a check it enables" do
    checks =
      "[{Trogon.Credo.Check.ExUnit.ApplicationEnvMutation, [hint: \"Read it through Acme.Config.\"]}]"

    issues = run_credo(config([{ExUnitPlugin, []}], checks), [{"sample_test.exs", @source}])

    assert [%{message: message}] = Enum.filter(issues, &(&1.check == ApplicationEnvMutation))
    assert message =~ "Read it through Acme.Config."
  end

  test "enables its checks under a config selected with --config-name" do
    issues =
      run_credo(config([{ExUnitPlugin, []}], "%{enabled: []}", "ci"), [{"sample_test.exs", @source}], [
        "--config-name",
        "ci"
      ])

    assert [%{check: ApplicationEnvMutation}] = issues
  end

  test "forwards hint to the check" do
    issues =
      run_credo(config([{ExUnitPlugin, [hint: "Read it through Acme.Config."]}]), [{"sample_test.exs", @source}])

    assert [%{message: message}] = issues
    assert message =~ "Read it through Acme.Config."
  end

  test "keeps the project's own entry for a check it enables" do
    checks =
      "%{enabled: [{Trogon.Credo.Check.ExUnit.ApplicationEnvMutation, [hint: \"Read it through Acme.Config.\"]}]}"

    issues = run_credo(config([{ExUnitPlugin, []}], checks), [{"sample_test.exs", @source}])

    assert [%{message: message}] = issues
    assert message =~ "Read it through Acme.Config."
  end

  test "leaves a check disabled when the project disables it" do
    checks = "%{enabled: [], disabled: [{Trogon.Credo.Check.ExUnit.ApplicationEnvMutation, []}]}"

    assert [] == run_credo(config([{ExUnitPlugin, []}], checks), [{"sample_test.exs", @source}])
  end

  test "leaves out the checks named in except" do
    assert [] ==
             run_credo(config([{ExUnitPlugin, [except: [ApplicationEnvMutation]]}]), [
               {"sample_test.exs", @source}
             ])
  end

  test "honors a disable comment naming the dedicated check" do
    source = """
    defmodule SampleTest do
      test "charges the configured tax rate" do
        # credo:disable-for-next-line Trogon.Credo.Check.ExUnit.ApplicationEnvMutation
        Application.put_env(:acme, :tax_rate, 0.07)
      end
    end
    """

    assert [] == run_credo(config([{ExUnitPlugin, []}]), [{"sample_test.exs", source}])
  end

  test "raises when except names a check the plugin does not enable" do
    assert_raise ArgumentError, ~r/invalid except/, fn ->
      run_credo(config([{ExUnitPlugin, [except: [Trogon.Credo.Check.Warning.ForbiddenUse]]}]), [
        {"sample_test.exs", @source}
      ])
    end
  end
end
