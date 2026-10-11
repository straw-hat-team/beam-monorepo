defmodule Trogon.Test.ReportFormatterTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.ReportFormatter

  @moduletag :tmp_dir

  describe "a run that passes" do
    test "writes only the summary", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, passed())
          finish_test(formatter, passed())
        end)

      assert report == "ALL PASSED | 2 tests, 2 passed | 5ms\n"
    end

    test "counts skipped and excluded tests without listing them", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, %{passed() | state: {:skipped, "not yet"}})
          finish_test(formatter, %{passed() | state: {:excluded, "due to integration filter"}})
        end)

      assert report == "ALL PASSED | 2 tests, 0 passed, 1 skipped, 1 excluded | 5ms\n"
    end
  end

  describe "a failing test" do
    test "writes its location, expression, and stacktrace, without ExUnit's frames", %{tmp_dir: tmp_dir} do
      result = 1

      report = run_failure(tmp_dir, fn -> assert result == 2 end)

      assert [
               "FAIL test charges the configured tax rate",
               "  test/my_app/billing_test.exs:12",
               "  assert result == 2",
               "  left:  1",
               "  " <> frame | _rest
             ] = String.split(report, "\n")

      assert frame =~ "test/trogon/test/report_formatter_test.exs:"
      assert report =~ "\n\nFAILURES | 1 tests, 0 passed, 1 failed | 5ms\n"
      refute report =~ "ExUnit.Assertions"
    end

    test "leaves out a value the expression shows as a literal", %{tmp_dir: tmp_dir} do
      result = 10

      report = run_failure(tmp_dir, fn -> assert 1 == result end)

      refute report =~ "left:"
      assert report =~ "right: 10"
    end

    test "writes a value a literal in the expression only resembles", %{tmp_dir: tmp_dir} do
      result = 1

      report = run_failure(tmp_dir, fn -> assert result == 10 end)

      assert report =~ "left:  1\n"
    end

    test "writes the value a pattern failed to match, not the pattern", %{tmp_dir: tmp_dir} do
      result = {:error, :timeout}

      report = run_failure(tmp_dir, fn -> assert {:ok, _value} = result end)

      assert report =~ "assert {:ok, _value} = result"
      assert report =~ "right: {:error, :timeout}"
      refute report =~ "left:"
      refute report =~ "match (=) failed"
    end

    test "writes the message of an assertion with no expression", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> flunk("the invoice was never sent") end)

      assert report =~ "  the invoice was never sent\n"
      refute report =~ "ex_unit_no_meaningful_value"
    end

    test "writes every line of the message of a missing message", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> assert_received :charged end)

      assert report =~ "  assert_received :charged\n"
      assert report =~ "  Assertion failed, no matching message after 0ms\n"
      assert report =~ "  The process mailbox is empty.\n"
    end

    test "writes the message of an exception", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> raise "boom" end)

      assert report =~ "  boom\n"
    end

    test "writes the reason of an exit", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> exit(:shutdown) end)

      assert report =~ "  ** (exit) shutdown\n"
    end

    test "writes a stacktrace entry for an anonymous function", %{tmp_dir: tmp_dir} do
      fun = fn -> :ok end
      stacktrace = [{fun, 0, [file: ~c"lib/my_app/billing.ex", line: 7]}]

      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, failed([{:error, %RuntimeError{message: "boom"}, stacktrace}]))
        end)

      assert report =~ "  boom\n  " <> Exception.format_stacktrace_entry(hd(stacktrace)) <> "\n"
    end

    test "numbers each of several failures", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, failed([failure(fn -> raise "first" end), failure(fn -> raise "second" end)]))
        end)

      assert report =~ "  failure 1 of 2\n  first\n"
      assert report =~ "  failure 2 of 2\n  second\n"
    end

    test "writes the logs it captured", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, %{failed([failure(fn -> raise "boom" end)]) | logs: "[warning] retrying\n"})
        end)

      assert report =~ "  [warning] retrying\n"
    end

    test "leaves out the logs it captured when told to", %{tmp_dir: tmp_dir} do
      report =
        run(
          tmp_dir,
          fn formatter ->
            finish_test(formatter, %{failed([failure(fn -> raise "boom" end)]) | logs: "[warning] retrying\n"})
          end,
          include_logs: false
        )

      refute report =~ "retrying"
    end
  end

  describe "a failing setup_all" do
    test "writes the failure once for its module", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          GenServer.cast(
            formatter,
            {:module_finished,
             %ExUnit.TestModule{
               name: MyApp.BillingTest,
               file: "test/my_app/billing_test.exs",
               state: {:failed, [failure(fn -> raise "no database" end)]}
             }}
          )

          finish_test(formatter, %{passed() | state: {:invalid, %ExUnit.TestModule{name: MyApp.BillingTest}}})
        end)

      assert report =~ "FAIL setup_all MyApp.BillingTest\n  test/my_app/billing_test.exs\n  no database\n"
      assert report =~ "FAILURES | 1 tests, 0 passed, 1 invalid | 5ms\n"
    end

    test "writes nothing for a module that passed", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          GenServer.cast(formatter, {:module_finished, %ExUnit.TestModule{name: MyApp.BillingTest, state: nil}})
        end)

      assert report == "ALL PASSED | 0 tests, 0 passed | 5ms\n"
    end
  end

  describe "max failures" do
    test "writes that the run stopped early", %{tmp_dir: tmp_dir} do
      report = run(tmp_dir, &GenServer.cast(&1, :max_failures_reached))

      assert report =~ "MAX FAILURES REACHED\n"
    end
  end

  describe "options" do
    test "writes to a path in a directory that does not exist yet", %{tmp_dir: tmp_dir} do
      path = Path.join([tmp_dir, "nested", "report.txt"])

      formatter = start_formatter(path: path)
      finish_suite(formatter)

      assert File.read!(path) =~ "ALL PASSED"
    end

    test "rejects an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:file_path\]/, fn ->
        ReportFormatter.init(trogon_test_report: [file_path: "report.txt"])
      end
    end

    test "rejects a path that is not a string" do
      assert_raise ArgumentError, ~r/:path to be a string/, fn ->
        ReportFormatter.init(trogon_test_report: [path: :report])
      end
    end

    test "rejects include_logs that is not a boolean" do
      assert_raise ArgumentError, ~r/:include_logs a boolean/, fn ->
        ReportFormatter.init(trogon_test_report: [include_logs: "yes"])
      end
    end
  end

  test "ignores the events it does not report", %{tmp_dir: tmp_dir} do
    report = run(tmp_dir, &GenServer.cast(&1, {:suite_started, []}))

    assert report == "ALL PASSED | 0 tests, 0 passed | 5ms\n"
  end

  defp run(tmp_dir, events, opts \\ []) do
    path = Path.join(tmp_dir, "report.txt")
    formatter = start_formatter(Keyword.put(opts, :path, path))
    events.(formatter)
    finish_suite(formatter)
    File.read!(path)
  end

  defp run_failure(tmp_dir, fun) do
    run(tmp_dir, &finish_test(&1, failed([failure(fun)])))
  end

  defp start_formatter(opts) do
    start_supervised!(%{
      id: ReportFormatter,
      start: {GenServer, :start_link, [ReportFormatter, [seed: 0, trogon_test_report: opts]]}
    })
  end

  defp finish_test(formatter, test), do: GenServer.cast(formatter, {:test_finished, test})

  defp finish_suite(formatter) do
    GenServer.cast(formatter, {:suite_finished, %{run: 5_000, async: nil, load: nil}})
    :sys.get_state(formatter)
  end

  defp passed do
    %ExUnit.Test{
      name: :"test charges the configured tax rate",
      module: MyApp.BillingTest,
      state: nil,
      tags: %{file: "test/my_app/billing_test.exs", line: 12},
      logs: ""
    }
  end

  defp failed(failures), do: %{passed() | state: {:failed, failures}}

  defp failure(fun) do
    fun.()
  catch
    kind, reason -> {kind, reason, __STACKTRACE__}
  else
    _result -> flunk("expected the function to fail")
  end
end
