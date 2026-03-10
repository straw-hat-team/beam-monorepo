defmodule Trogon.ExunitReporter.Event do
  @moduledoc """
  Formats ExUnit events as compact plain text optimized for AI agent token consumption.

  Only failures produce detailed output. Passing tests are counted but not listed.
  """

  @doc """
  Formats a failed `%ExUnit.Test{}` as a compact text block.

  Returns `nil` for non-failed tests (they only contribute to counters).
  """
  @spec format_test(ExUnit.Test.t(), keyword()) :: iodata() | nil
  def format_test(%ExUnit.Test{state: {:failed, failures}} = test, opts) do
    header = "FAIL #{test.name}"
    location = "  #{test.tags[:file]}:#{test.tags[:line]}"

    failure_lines =
      failures
      |> Enum.with_index(1)
      |> Enum.map(fn {failure, idx} ->
        format_failure(failure, idx, length(failures))
      end)

    logs = format_logs(test, opts)

    [header, "\n", location, "\n" | failure_lines] ++ logs
  end

  def format_test(_test, _opts), do: nil

  @doc """
  Formats the suite summary as a single dense line.

  When all tests pass, this is the only output — one line an agent can read
  and immediately stop processing.
  """
  @spec format_summary(map(), map()) :: iodata()
  def format_summary(times_us, counters) do
    run_ms = div(times_us.run, 1000)

    status =
      if counters.failed == 0 and counters.invalid == 0,
        do: "ALL PASSED",
        else: "FAILURES"

    parts =
      [
        "#{counters.total} tests",
        "#{counters.passed} passed",
        if(counters.failed > 0, do: "#{counters.failed} failed"),
        if(counters.skipped > 0, do: "#{counters.skipped} skipped"),
        if(counters.excluded > 0, do: "#{counters.excluded} excluded"),
        if(counters.invalid > 0, do: "#{counters.invalid} invalid")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    [status, " | ", parts, " | #{run_ms}ms\n"]
  end

  @doc """
  Formats the max failures reached marker.
  """
  @spec format_max_failures_reached() :: iodata()
  def format_max_failures_reached do
    ["MAX FAILURES REACHED\n"]
  end

  # -- Private helpers --

  defp format_failure({_kind, reason, stacktrace}, idx, total) do
    prefix = if total > 1, do: "  [#{idx}/#{total}] ", else: ""

    lines =
      case reason do
        %ExUnit.AssertionError{} = err ->
          [prefix]
          |> append_if(err.expr, "  #{format_expr(err.expr)}\n")
          |> append_left_right(err)

        %{__exception__: true} = err ->
          [prefix, "  ", Exception.message(err), "\n"]

        other ->
          [prefix, "  ", inspect(other), "\n"]
      end

    case format_stacktrace(stacktrace) do
      [] -> lines
      frames -> lines ++ Enum.map(frames, &["  ", &1, "\n"])
    end
  end

  defp format_expr(nil), do: nil

  defp format_expr(expr) do
    Macro.to_string(expr)
  rescue
    _ -> inspect(expr)
  end

  defp format_value(:ex_unit_no_meaningful_value), do: nil
  defp format_value(value), do: inspect(value, pretty: true, limit: 50)

  defp append_if(lines, nil, _text), do: lines
  defp append_if(lines, _value, text), do: lines ++ [text]

  defp append_left_right(lines, %ExUnit.AssertionError{} = err) do
    left = format_value(err.left)
    right = format_value(err.right)
    expr_str = format_expr(err.expr)

    lines
    |> append_if_novel(left, "  left:  #{left}\n", expr_str)
    |> append_if_novel(right, "  right: #{right}\n", expr_str)
  end

  defp append_if_novel(lines, nil, _text, _expr_str), do: lines

  defp append_if_novel(lines, _value, text, nil), do: lines ++ [text]

  defp append_if_novel(lines, value, text, expr_str) do
    if String.contains?(expr_str, value) do
      lines
    else
      lines ++ [text]
    end
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    |> Enum.reject(&internal_frame?/1)
    |> Enum.map(&format_frame/1)
  end

  defp format_stacktrace(_), do: []

  defp format_frame({mod, fun, arity, location}) do
    file = Keyword.get(location, :file, ~c"nofile") |> to_string()
    line = Keyword.get(location, :line, 0)
    "#{file}:#{line} #{inspect(mod)}.#{fun}/#{arity_value(arity)}"
  end

  defp format_frame(other), do: inspect(other)

  defp arity_value(args) when is_list(args), do: length(args)
  defp arity_value(n) when is_integer(n), do: n

  @internal_modules [ExUnit, ExUnit.Runner, ExUnit.Assertions]

  defp internal_frame?({mod, _fun, _arity, _location}) do
    mod_string = Atom.to_string(mod)

    Enum.any?(@internal_modules, fn internal ->
      String.starts_with?(mod_string, Atom.to_string(internal))
    end)
  end

  defp internal_frame?(_), do: false

  defp format_logs(%ExUnit.Test{logs: logs}, opts) when is_binary(logs) and logs != "" do
    if Keyword.get(opts, :include_logs, true) do
      indent_lines(logs, "  ")
    else
      []
    end
  end

  defp format_logs(_test, _opts), do: []

  defp indent_lines(text, prefix) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&[prefix, &1, "\n"])
  end
end
