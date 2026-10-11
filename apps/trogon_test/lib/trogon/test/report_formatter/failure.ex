defmodule Trogon.Test.ReportFormatter.Failure do
  @moduledoc false

  @no_value :ex_unit_no_meaningful_value
  @indent "  "

  @spec format_test(ExUnit.Test.t(), boolean()) :: iodata() | nil
  def format_test(%ExUnit.Test{state: {:failed, failures}} = test, include_logs) do
    [
      ["FAIL #{test.name}", format_parameters(test.parameters), "\n"],
      indent("#{Path.relative_to_cwd(test.tags.file)}:#{test.tags.line}"),
      format_failures(failures),
      if(include_logs, do: format_logs(test.logs), else: []),
      "\n"
    ]
  end

  def format_test(%ExUnit.Test{}, _include_logs), do: nil

  @spec format_module(ExUnit.TestModule.t()) :: iodata() | nil
  def format_module(%ExUnit.TestModule{state: {:failed, failures}} = test_module) do
    [
      ["FAIL setup_all #{inspect(test_module.name)}", format_parameters(test_module.parameters), "\n"],
      indent(Path.relative_to_cwd(test_module.file)),
      format_failures(failures),
      "\n"
    ]
  end

  def format_module(%ExUnit.TestModule{}), do: nil

  defp format_parameters(parameters) when map_size(parameters) == 0, do: []
  defp format_parameters(parameters), do: [" ", inspect(parameters)]

  defp format_failures([failure]), do: format_failure(failure)

  defp format_failures(failures) do
    total = length(failures)

    for {failure, index} <- Enum.with_index(failures, 1) do
      [indent("failure #{index} of #{total}"), format_failure(failure)]
    end
  end

  defp format_failure({kind, reason, stacktrace}) do
    [format_reason(kind, reason, stacktrace), format_stacktrace(stacktrace)]
  end

  defp format_reason(:error, %ExUnit.AssertionError{} = error, _stacktrace) do
    [
      format_expr(error.expr),
      format_message(error),
      format_side("left:  ", error.left, left_shown?(error)),
      format_side("right: ", error.right, right_shown?(error)),
      format_mailbox(error.context)
    ]
  end

  defp format_reason(:error, reason, stacktrace) do
    :error |> Exception.normalize(reason, stacktrace) |> Exception.message() |> indent()
  end

  defp format_reason(kind, reason, stacktrace) do
    kind |> Exception.format_banner(reason, stacktrace) |> indent()
  end

  defp format_expr(@no_value), do: []
  defp format_expr(expr), do: expr |> Macro.to_string() |> indent()

  # ExUnit's own messages for a failed comparison or match only repeat what the
  # expression already shows.
  defp format_message(%ExUnit.AssertionError{message: message, expr: expr}) when expr != @no_value do
    if message =~ ~r/\A(Assertion with \S+ failed|match \(\S+\) failed)\z/, do: [], else: indent(message)
  end

  defp format_message(%ExUnit.AssertionError{message: message}), do: indent(message)

  defp format_side(_label, @no_value, _shown?), do: []
  defp format_side(_label, _value, true), do: []
  defp format_side(label, value, false), do: indent(label <> inspect(value, pretty: true, limit: 50))

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

  defp format_stacktrace(stacktrace) do
    for entry <- stacktrace, not ex_unit_frame?(entry), do: indent(Exception.format_stacktrace_entry(entry))
  end

  defp ex_unit_frame?({module, _function, _arity, _location}) when is_atom(module) do
    module == ExUnit or String.starts_with?(Atom.to_string(module), "Elixir.ExUnit.")
  end

  defp ex_unit_frame?(_entry), do: false

  defp format_logs(logs) when is_binary(logs) and logs != "", do: indent(logs)
  defp format_logs(_logs), do: []

  defp indent(text) do
    for line <- String.split(text, "\n", trim: true), do: [@indent, line, "\n"]
  end
end
