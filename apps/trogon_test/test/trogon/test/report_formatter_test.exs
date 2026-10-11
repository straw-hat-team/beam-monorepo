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
               "  " <> location,
               "  assert result == 2",
               "  left:  1",
               "  " <> frame | _rest
             ] = String.split(report, "\n")

      assert location == from_root("test/my_app/billing_test.exs:12")
      assert frame =~ "test/trogon/test/report_formatter_test.exs:"
      assert report =~ "\n\nFAILURES | 1 tests, 0 passed, 1 failed | 5ms | seed 0\n"
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

    test "writes the values a pattern pinned", %{tmp_dir: tmp_dir} do
      id = 1
      invoice = %{id: 2}

      report = run_failure(tmp_dir, fn -> assert %{id: ^id} = invoice end)

      assert report =~ "  The following variables were pinned:\n    id = 1\n"
      assert report =~ "  right: %{id: 2}\n"
    end

    test "writes the messages in the mailbox when none matched", %{tmp_dir: tmp_dir} do
      id = 1
      send(self(), {:charged, 2})

      report = run_failure(tmp_dir, fn -> assert_received {:charged, ^id} end)

      assert report =~ "  Showing 1 of 1 message in the mailbox\n  received: {:charged, 2}\n"
    end

    test "writes the message of an exception", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> raise "boom" end)

      assert report =~ "  boom\n"
    end

    test "writes the reason of an exit", %{tmp_dir: tmp_dir} do
      report = run_failure(tmp_dir, fn -> exit(:shutdown) end)

      assert report =~ "  ** (exit) shutdown\n"
    end

    test "writes only the line of a frame in the test's own module", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, %{failed([failure(fn -> raise "boom" end)]) | module: __MODULE__})
        end)

      assert report =~ ~r/\n  #{Regex.escape(from_root(__ENV__.file))}:\d+\n/
      refute report =~ inspect(__MODULE__)
    end

    test "writes the whole frame in the test's own module when it has no file", %{tmp_dir: tmp_dir} do
      stacktrace = [{MyApp.BillingTest, :"test charges the configured tax rate", 1, []}]

      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, failed([{:error, %RuntimeError{message: "boom"}, stacktrace}]))
        end)

      assert report =~ "  boom\n  " <> Exception.format_stacktrace_entry(hd(stacktrace)) <> "\n"
    end

    test "writes a timeout without ExUnit's advice on changing it", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, failed([{:error, %ExUnit.TimeoutError{timeout: 50, type: "test"}, []}]))
        end)

      assert report =~ "  test timed out after 50ms\n\n"
    end

    test "writes the expression of a doctest as written", %{tmp_dir: tmp_dir} do
      error = %ExUnit.AssertionError{expr: "1 + 1 === 3", message: "Doctest failed", left: 2, right: 3}

      report = run(tmp_dir, &finish_test(&1, failed([{:error, error, []}])))

      assert report =~ "  1 + 1 === 3\n  Doctest failed\n  left:  2\n  right: 3\n"
    end

    test "leaves out the frame ExUnit's runner ends every stacktrace with", %{tmp_dir: tmp_dir} do
      stacktrace = [
        {MyApp.Billing, :charge, 1, []},
        {:timer, :tc, 2, [file: ~c"timer.erl", line: 599]},
        {ExUnit.Runner, :exec_test, 2, [file: ~c"lib/ex_unit/runner.ex", line: 512]}
      ]

      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, failed([{:error, %RuntimeError{message: "boom"}, stacktrace}]))
        end)

      assert report =~ "  boom\n  MyApp.Billing.charge/1\n\n"
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

  describe "a failing comparison" do
    test "writes only the keys where two maps differ, however large", %{tmp_dir: tmp_dir} do
      expected = Map.new(1..100, &{&1, &1})
      result = Map.put(expected, 100, 0)

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  assert result == expected\n  at [100]\n    left:  0\n    right: 100\n"
      refute report =~ "%{"
    end

    test "writes a key only one side has", %{tmp_dir: tmp_dir} do
      result = Map.new(id: 1, status: :paid)
      expected = Map.new(id: 1, paid_at: ~D[2026-01-01])

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  at [:paid_at]\n    left:  (missing)\n    right: ~D[2026-01-01]\n"
      assert report =~ "  at [:status]\n    left:  :paid\n    right: (missing)\n"
    end

    test "walks into structs of the same type, lists of the same length, and tuples", %{tmp_dir: tmp_dir} do
      result = %URI{host: "example.com", path: [{:line, 1}, {:line, 2}]}
      expected = %URI{host: "example.com", path: [{:line, 1}, {:line, 3}]}

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  at [:path, 1, 1]\n    left:  2\n    right: 3\n"
    end

    test "leaves out what == finds equal", %{tmp_dir: tmp_dir} do
      result = Map.new(tax: 1, total: 2)
      expected = Map.new(tax: 1.0, total: 3)

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  at [:total]\n"
      refute report =~ "at [:tax]"
    end

    test "writes what === finds different", %{tmp_dir: tmp_dir} do
      result = Map.new(tax: 1)
      expected = Map.new(tax: 1.0)

      report = run_failure(tmp_dir, fn -> assert result === expected end)

      assert report =~ "  at [:tax]\n    left:  1\n    right: 1.0\n"
    end

    test "writes whole values that cannot be walked into", %{tmp_dir: tmp_dir} do
      result = URI.new!("https://example.com")
      expected = Map.new(host: "example.com")

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  left:  %URI{"
      assert report =~ ~s(  right: %{host: "example.com"}\n)
    end

    test "writes whole lists of different lengths", %{tmp_dir: tmp_dir} do
      result = [1, 2, 3]
      expected = [1, 3]

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ "  left:  [1, 2, 3]\n  right: [1, 3]\n"
    end

    test "writes a value without truncating it", %{tmp_dir: tmp_dir} do
      result = String.duplicate("a", 5_000) <> "b"
      expected = String.duplicate("a", 5_000) <> "c"

      report = run_failure(tmp_dir, fn -> assert result == expected end)

      assert report =~ ~s(ab"\n)
      assert report =~ ~s(ac"\n)
    end
  end

  describe "a parameterized test" do
    test "writes the parameters a failing instance ran with", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, %{failed([failure(fn -> raise "boom" end)]) | parameters: %{currency: :usd}})

          GenServer.cast(
            formatter,
            {:module_finished,
             %ExUnit.TestModule{
               name: MyApp.BillingTest,
               file: "test/my_app/billing_test.exs",
               parameters: %{currency: :eur},
               state: {:failed, [failure(fn -> raise "no database" end)]}
             }}
          )
        end)

      assert report =~ "FAIL test charges the configured tax rate %{currency: :usd}\n"
      assert report =~ "FAIL setup_all MyApp.BillingTest %{currency: :eur}\n"
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

      assert report =~
               "FAIL setup_all MyApp.BillingTest\n  #{from_root("test/my_app/billing_test.exs")}\n  no database\n"

      assert report =~ "FAILURES | 1 tests, 0 passed, 1 invalid, 1 setup_all failed | 5ms | seed 0\n"
    end

    test "fails the run even when every test in the module passed", %{tmp_dir: tmp_dir} do
      report =
        run(tmp_dir, fn formatter ->
          finish_test(formatter, passed())

          GenServer.cast(
            formatter,
            {:module_finished,
             %ExUnit.TestModule{
               name: MyApp.BillingTest,
               file: "test/my_app/billing_test.exs",
               state: {:failed, [failure(fn -> raise "on_exit failed" end)]}
             }}
          )
        end)

      assert report =~ "FAILURES | 1 tests, 1 passed, 1 setup_all failed | 5ms | seed 0\n"
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
    test "leaves out the seed of a run that has none", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "report.txt")
      formatter = start_formatter([path: path], [])
      finish_test(formatter, failed([failure(fn -> raise "boom" end)]))
      finish_suite(formatter)

      assert File.read!(path) =~ "FAILURES | 1 tests, 0 passed, 1 failed | 5ms\n"
    end

    test "writes to standard output without a path" do
      report =
        ExUnit.CaptureIO.capture_io(fn ->
          formatter = start_formatter([])
          finish_test(formatter, passed())
          finish_suite(formatter)
        end)

      assert report == "ALL PASSED | 1 tests, 1 passed | 5ms\n"
    end

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
      assert_raise ArgumentError, ~r/:path to be nil or a string/, fn ->
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

  defp start_formatter(opts, config \\ [seed: 0]) do
    start_supervised!(%{
      id: ReportFormatter,
      start: {GenServer, :start_link, [ReportFormatter, [{:trogon_test_report, opts} | config]]}
    })
  end

  defp finish_test(formatter, test), do: GenServer.cast(formatter, {:test_finished, test})

  defp finish_suite(formatter) do
    GenServer.cast(formatter, {:suite_finished, %{run: 5_000, async: nil, load: nil}})
    :sys.get_state(formatter)
  end

  defp from_root(path) do
    umbrella_file = Mix.Project.parent_umbrella_project_file()
    root = if umbrella_file, do: Path.dirname(umbrella_file), else: File.cwd!()
    path |> Path.expand() |> Path.relative_to(root)
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
