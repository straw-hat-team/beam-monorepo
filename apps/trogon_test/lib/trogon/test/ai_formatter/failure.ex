defmodule Trogon.Test.AIFormatter.Failure do
  @moduledoc false

  alias Trogon.Test.AIFormatter.Diff

  @no_value :ex_unit_no_meaningful_value
  @indent "  "
  @compared [:==, :===]

  @spec format_test(ExUnit.Test.t(), Path.t(), boolean()) :: iodata() | nil
  def format_test(%ExUnit.Test{state: {:failed, failures}} = test, root, include_logs) do
    [
      ["FAIL #{test.name}", format_parameters(test.parameters), "\n"],
      indent("#{relative(test.tags.file, root)}:#{test.tags.line}"),
      format_failures(failures, test.module, root),
      if(include_logs, do: format_logs(test.logs), else: []),
      "\n"
    ]
  end

  def format_test(%ExUnit.Test{}, _root, _include_logs), do: nil

  @spec format_module(ExUnit.TestModule.t(), Path.t()) :: iodata() | nil
  def format_module(%ExUnit.TestModule{state: {:failed, failures}} = test_module, root) do
    [
      ["FAIL setup_all #{inspect(test_module.name)}", format_parameters(test_module.parameters), "\n"],
      indent(relative(test_module.file, root)),
      format_failures(failures, test_module.name, root),
      "\n"
    ]
  end

  def format_module(%ExUnit.TestModule{}, _root), do: nil

  defp format_parameters(parameters) when map_size(parameters) == 0, do: []
  defp format_parameters(parameters), do: [" ", inspect(parameters)]

  defp format_failures([failure], test_module, root), do: format_failure(failure, test_module, root)

  defp format_failures(failures, test_module, root) do
    total = length(failures)

    for {failure, index} <- Enum.with_index(failures, 1) do
      [indent("failure #{index} of #{total}"), format_failure(failure, test_module, root)]
    end
  end

  defp format_failure({kind, reason, stacktrace}, test_module, root) do
    [format_reason(kind, reason, stacktrace), format_stacktrace(stacktrace, test_module, root)]
  end

  defp format_reason(:error, %ExUnit.AssertionError{} = error, _stacktrace) do
    [format_expr(error.expr), format_message(error), format_values(error), format_mailbox(error.context)]
  end

  # ExUnit's message goes on to explain how to change the timeout.
  defp format_reason(:error, %ExUnit.TimeoutError{} = error, _stacktrace) do
    indent("#{error.type} timed out after #{error.timeout}ms")
  end

  defp format_reason(:error, reason, stacktrace) do
    :error |> Exception.normalize(reason, stacktrace) |> Exception.message() |> indent()
  end

  defp format_reason(kind, reason, stacktrace) do
    kind |> Exception.format_banner(reason, stacktrace) |> indent()
  end

  defp format_expr(@no_value), do: []
  defp format_expr(expr) when is_binary(expr), do: indent(expr)
  defp format_expr(expr), do: expr |> Macro.to_string() |> indent()

  # ExUnit's own messages for a failed comparison or match only repeat what the
  # expression already shows.
  defp format_message(%ExUnit.AssertionError{message: message, expr: expr}) when expr != @no_value do
    if message =~ ~r/\A(Assertion with \S+ failed|match \(\S+\) failed)\z/, do: [], else: indent(message)
  end

  defp format_message(%ExUnit.AssertionError{message: message}), do: indent(message)

  # A comparison of two maps, lists, or tuples writes only the places where they
  # differ, so a large value never hides the difference behind a truncation.
  defp format_values(%ExUnit.AssertionError{expr: {:assert, _meta, [{operator, _op_meta, [_, _]}]}} = error)
       when operator in @compared do
    case Diff.changes(error.left, error.right, comparison(operator)) do
      [{[_ | _], _left, _right} | _rest] = changes -> Enum.map(changes, &format_change/1)
      _whole_values -> format_sides(error)
    end
  end

  defp format_values(error), do: format_sides(error)

  defp comparison(:==), do: &==/2
  defp comparison(:===), do: &===/2

  defp format_change({path, left, right}) do
    indent(
      "at #{inspect(path, charlists: :as_lists)}\n  left:  #{format_changed(left)}\n  right: #{format_changed(right)}"
    )
  end

  defp format_changed({:value, value}), do: inspect_whole(value)
  defp format_changed(:missing), do: "(missing)"

  defp format_sides(error) do
    [
      format_side("left:  ", error.left, left_shown?(error)),
      format_side("right: ", error.right, right_shown?(error))
    ]
  end

  defp format_side(_label, @no_value, _shown?), do: []
  defp format_side(_label, _value, true), do: []
  defp format_side(label, value, false), do: indent(label <> inspect_whole(value))

  defp inspect_whole(value), do: inspect(value, pretty: true, limit: :infinity, printable_limit: :infinity)

  # ExUnit's message counts the messages in the mailbox, but only the context
  # holds them.
  defp format_mailbox({:mailbox, _pins, messages}) do
    for message <- messages, do: indent("received: " <> inspect(message, limit: 50))
  end

  defp format_mailbox(_context), do: []

  # A value is left out when the expression already shows it: a literal operand,
  # or the pattern of a match or a received message, which ExUnit records as code.
  defp left_shown?(%ExUnit.AssertionError{context: {:match, _pins}}), do: true
  defp left_shown?(%ExUnit.AssertionError{context: {:mailbox, _pins, _mailbox}}), do: true
  defp left_shown?(%ExUnit.AssertionError{expr: expr}), do: literal_operand?(expr, 0)

  defp right_shown?(%ExUnit.AssertionError{expr: expr}), do: literal_operand?(expr, 1)

  defp literal_operand?({assertion, _meta, [{_operator, _op_meta, [_left, _right] = operands}]}, index)
       when assertion in [:assert, :refute] do
    operands |> Enum.at(index) |> Macro.quoted_literal?()
  end

  defp literal_operand?(_expr, _index), do: false

  defp format_stacktrace(stacktrace, test_module, root) do
    for entry <- stacktrace |> Enum.reject(&ex_unit_frame?/1) |> drop_runner_frame(),
        do: indent(format_frame(entry, test_module, root))
  end

  # ExUnit's runner times every test, so a stacktrace that reaches it ends in
  # the same frame once ExUnit's own are left out.
  defp drop_runner_frame(stacktrace) do
    case List.last(stacktrace) do
      {:timer, :tc, _arity, _location} -> Enum.drop(stacktrace, -1)
      _entry -> stacktrace
    end
  end

  # The header already names the test, so a frame in its module needs only the
  # line. A frame elsewhere keeps the application, module, and function it ran.
  defp format_frame({test_module, _function, _arity, location} = entry, test_module, root) do
    case location[:file] do
      nil -> Exception.format_stacktrace_entry(entry)
      file -> "#{relative(List.to_string(file), root)}:#{location[:line]}"
    end
  end

  defp format_frame(entry, _test_module, _root), do: Exception.format_stacktrace_entry(entry)

  defp ex_unit_frame?({module, _function, _arity, _location}) when is_atom(module) do
    module == ExUnit or String.starts_with?(Atom.to_string(module), "Elixir.ExUnit.")
  end

  defp ex_unit_frame?(_entry), do: false

  defp format_logs(logs) when is_binary(logs) and logs != "", do: indent(logs)
  defp format_logs(_logs), do: []

  defp relative(path, root), do: path |> Path.expand() |> Path.relative_to(root)

  defp indent(text) do
    for line <- String.split(text, "\n", trim: true), do: [@indent, line, "\n"]
  end
end
