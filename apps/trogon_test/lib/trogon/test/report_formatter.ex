defmodule Trogon.Test.ReportFormatter do
  @moduledoc """
  An ExUnit formatter that writes a compact plain-text report of the run, for a
  tool or an agent to read instead of the CLI formatter's output.

  A passing test writes nothing, so a run that passes is one summary line. A
  failing test writes its location, the assertion or error that failed, the
  values the assertion compared that its code does not already show, the
  stacktrace without ExUnit's own frames, and the logs it captured. A
  `setup_all` that fails is reported once, for its module.

  Run it in place of the CLI formatter, and the report goes to standard output,
  for the caller to read, pipe, or redirect like any other output:

      mix test --formatter Trogon.Test.ReportFormatter

  To keep the terminal output the same and read the report on the side, run it
  next to the CLI formatter in `test/test_helper.exs` and give it a `:path`:

      ExUnit.start(
        formatters: [ExUnit.CLIFormatter, Trogon.Test.ReportFormatter],
        trogon_test_report: [path: "tmp/test-report.txt"]
      )

  A failing run writes:

      FAIL test charges the configured tax rate
        test/my_app/billing_test.exs:12
        assert tax_rate == 0.07
        left:  0.0
        test/my_app/billing_test.exs:15: MyApp.BillingTest."test charges the configured tax rate"/1

      FAILURES | 42 tests, 41 passed, 1 failed | 150ms

  ## Options

  Given under the `:trogon_test_report` key of the ExUnit configuration:

    * `:path` - a file to write the report to instead of standard output,
      relative to the directory `mix test` runs in. The file is replaced on
      every run. Defaults to `nil`, standard output.

    * `:include_logs` - whether a failing test's captured logs are written
      under it. Defaults to `true`.
  """

  use GenServer

  alias Trogon.Test.ReportFormatter.Failure
  alias Trogon.Test.ReportFormatter.Tally

  @enforce_keys [:device, :include_logs, :tally]
  defstruct [:device, :include_logs, :tally]

  @doc false
  @impl GenServer
  def init(config) do
    {path, include_logs} = config |> Keyword.get(:trogon_test_report, []) |> options!()

    {:ok, %__MODULE__{device: open(path), include_logs: include_logs, tally: %Tally{}}}
  end

  @doc false
  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    write(state, Failure.format_test(test, state.include_logs))
    {:noreply, %{state | tally: Tally.count(state.tally, test)}}
  end

  def handle_cast({:module_finished, %ExUnit.TestModule{} = test_module}, state) do
    write(state, Failure.format_module(test_module))
    {:noreply, %{state | tally: Tally.count_module(state.tally, test_module)}}
  end

  def handle_cast(:max_failures_reached, state) do
    write(state, "MAX FAILURES REACHED\n\n")
    {:noreply, state}
  end

  def handle_cast({:suite_finished, %{run: run_us}}, state) do
    write(state, Tally.format(state.tally, run_us))
    close(state.device)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp options!(opts) do
    opts = Keyword.validate!(opts, path: nil, include_logs: true)

    case {opts[:path], opts[:include_logs]} do
      {path, include_logs} when (is_nil(path) or is_binary(path)) and is_boolean(include_logs) ->
        {path, include_logs}

      _invalid ->
        raise ArgumentError,
              "expected :path to be nil or a string and :include_logs a boolean, got: #{inspect(opts)}"
    end
  end

  defp open(nil), do: :stdio

  defp open(path) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.open!(path, [:write, :utf8])
  end

  defp close(:stdio), do: :ok
  defp close(device), do: File.close(device)

  defp write(_state, nil), do: :ok
  defp write(state, iodata), do: IO.write(state.device, iodata)
end
