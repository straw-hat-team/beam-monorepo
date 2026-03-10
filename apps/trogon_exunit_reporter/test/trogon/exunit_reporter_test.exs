defmodule Trogon.ExunitReporterTest do
  use ExUnit.Case, async: true

  alias Trogon.ExunitReporter

  describe "passing tests produce no output" do
    @tag :tmp_dir
    test "only summary appears when all tests pass", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      cast_test(pid, :passing)
      cast_test(pid, :passing)
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "ALL PASSED"
      assert output =~ "2 tests, 2 passed"
      refute output =~ "FAIL"
    end
  end

  describe "failing tests produce diagnostic output" do
    @tag :tmp_dir
    test "includes assertion details for failed test", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      assertion_error = %ExUnit.AssertionError{
        message: "Assertion with == failed",
        expr: quote(do: assert(1 == 2)),
        left: 1,
        right: 2
      }

      cast_test(pid, {:failed, assertion_error, "test/math_test.exs", 11})
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "FAIL"
      assert output =~ "assert 1 == 2"
      refute output =~ "left:"
      refute output =~ "right:"
      assert output =~ "FAILURES"
      assert output =~ "1 failed"
    end

    @tag :tmp_dir
    test "includes left/right when expression uses variables", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      assertion_error = %ExUnit.AssertionError{
        message: "Assertion with == failed",
        expr: quote(do: assert(result == expected)),
        left: [1, 2, 3],
        right: [1, 2, 4]
      }

      cast_test(pid, {:failed, assertion_error, "test/var_test.exs", 5})
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "assert result == expected"
      assert output =~ "left:"
      assert output =~ "[1, 2, 3]"
      assert output =~ "right:"
      assert output =~ "[1, 2, 4]"
    end

    @tag :tmp_dir
    test "includes runtime error details", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      cast_test(pid, {:failed, %RuntimeError{message: "boom"}, "test/boom_test.exs", 5})
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "FAIL"
      assert output =~ "boom"
    end

    @tag :tmp_dir
    test "includes stacktrace with internal frames filtered", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      stacktrace = [
        {MyApp.MathTest, :"test math works", 1, [file: ~c"test/math_test.exs", line: 11]},
        {ExUnit.Assertions, :assert, 1, [file: ~c"lib/ex_unit/assertions.ex", line: 100]}
      ]

      test_struct = %ExUnit.Test{
        name: :"test math works",
        module: MyApp.MathTest,
        state: {:failed, [{:error, %RuntimeError{message: "oops"}, stacktrace}]},
        time: 456,
        tags: %{file: "test/math_test.exs", line: 10},
        logs: ""
      }

      GenServer.cast(pid, {:test_finished, test_struct})
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "test/math_test.exs:11"
      refute output =~ "assertions.ex"
    end

    @tag :tmp_dir
    test "includes captured logs when configured", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      test_struct = %ExUnit.Test{
        name: :"test with logs",
        module: MyApp.LogTest,
        state: {:failed, [{:error, %RuntimeError{message: "boom"}, []}]},
        time: 100,
        tags: %{file: "test/log_test.exs", line: 1},
        logs: "[warning] something went wrong\n"
      }

      GenServer.cast(pid, {:test_finished, test_struct})
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "something went wrong"
    end

    @tag :tmp_dir
    test "excludes logs when include_logs is false", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path, include_logs: false)

      test_struct = %ExUnit.Test{
        name: :"test with logs",
        module: MyApp.LogTest,
        state: {:failed, [{:error, %RuntimeError{message: "boom"}, []}]},
        time: 100,
        tags: %{file: "test/log_test.exs", line: 1},
        logs: "[warning] something went wrong\n"
      }

      GenServer.cast(pid, {:test_finished, test_struct})
      finish_suite(pid)

      output = read_report(file_path)
      refute output =~ "something went wrong"
    end
  end

  describe "skipped and excluded tests" do
    @tag :tmp_dir
    test "counted in summary but produce no output lines", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      skipped = %ExUnit.Test{
        name: :"test skipped",
        module: MyApp.SkipTest,
        state: {:skipped, "not implemented"},
        time: 0,
        tags: %{file: "test/skip_test.exs", line: 1},
        logs: ""
      }

      excluded = %ExUnit.Test{
        name: :"test excluded",
        module: MyApp.ExcludeTest,
        state: {:excluded, "excluded by tag"},
        time: 0,
        tags: %{file: "test/exclude_test.exs", line: 1},
        logs: ""
      }

      GenServer.cast(pid, {:test_finished, skipped})
      GenServer.cast(pid, {:test_finished, excluded})
      finish_suite(pid)

      output = read_report(file_path)
      refute output =~ "FAIL"
      assert output =~ "1 skipped"
      assert output =~ "1 excluded"
      assert output =~ "2 tests"
    end
  end

  describe "summary line" do
    @tag :tmp_dir
    test "shows timing in milliseconds", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      cast_test(pid, :passing)
      GenServer.cast(pid, {:suite_finished, %{run: 150_000, load: nil, async: nil}})
      Process.sleep(20)

      output = read_report(file_path)
      assert output =~ "150ms"
    end
  end

  describe "max_failures_reached" do
    @tag :tmp_dir
    test "writes marker to report", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      GenServer.cast(pid, :max_failures_reached)
      finish_suite(pid)

      output = read_report(file_path)
      assert output =~ "MAX FAILURES REACHED"
    end
  end

  describe "mixed pass and fail" do
    @tag :tmp_dir
    test "only failures appear, summary reflects all", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "report.txt")
      pid = start_reporter(file_path)

      cast_test(pid, :passing)
      cast_test(pid, :passing)
      cast_test(pid, {:failed, %RuntimeError{message: "oops"}, "test/fail_test.exs", 10})
      finish_suite(pid)

      output = read_report(file_path)

      lines = String.split(output, "\n", trim: true)
      fail_lines = Enum.filter(lines, &String.starts_with?(&1, "FAIL "))
      assert length(fail_lines) == 1

      assert output =~ "3 tests, 2 passed, 1 failed"
    end
  end

  # -- Test helpers --

  defp start_reporter(file_path, extra_opts \\ []) do
    opts = [
      seed: 42,
      trogon_exunit_reporter: Keyword.merge([file_path: file_path], extra_opts)
    ]

    {:ok, pid} = GenServer.start_link(ExunitReporter, opts)
    pid
  end

  defp cast_test(pid, :passing) do
    test_struct = %ExUnit.Test{
      name: :"test passes",
      module: MyApp.Test,
      state: nil,
      time: 100,
      tags: %{file: "test/my_test.exs", line: 1},
      logs: ""
    }

    GenServer.cast(pid, {:test_finished, test_struct})
  end

  defp cast_test(pid, {:failed, reason, file, line}) do
    test_struct = %ExUnit.Test{
      name: :"test fails",
      module: MyApp.Test,
      state: {:failed, [{:error, reason, []}]},
      time: 200,
      tags: %{file: file, line: line},
      logs: ""
    }

    GenServer.cast(pid, {:test_finished, test_struct})
  end

  defp finish_suite(pid) do
    GenServer.cast(pid, {:suite_finished, %{run: 5000, load: nil, async: nil}})
    Process.sleep(20)
  end

  defp read_report(file_path) do
    File.read!(file_path)
  end
end
