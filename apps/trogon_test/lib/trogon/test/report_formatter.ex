defmodule Trogon.Test.ReportFormatter do
  @moduledoc """
  An ExUnit formatter that writes a compact plain-text report of the run to a
  file, for a tool or an agent to read instead of the terminal output.

  A passing test writes nothing, so a run that passes is one summary line. A
  failing test writes its location, the assertion or error that failed, the
  values the assertion compared that its code does not already show, the
  stacktrace without ExUnit's own frames, and the logs it captured. A
  `setup_all` that fails is reported once, for its module.

  Run it next to the CLI formatter in `test/test_helper.exs`, so the terminal
  output stays the same:

      ExUnit.start(formatters: [ExUnit.CLIFormatter, Trogon.Test.ReportFormatter])

  A failing run writes:

      FAIL test charges the configured tax rate
        test/my_app/billing_test.exs:12
        assert tax_rate == 0.07
        left:  0.0
        test/my_app/billing_test.exs:15: MyApp.BillingTest."test charges the configured tax rate"/1

      FAILURES | 42 tests, 41 passed, 1 failed | 150ms

  ## Options

  Given under the `:trogon_test_report` key of the ExUnit configuration:

      ExUnit.start(
        formatters: [ExUnit.CLIFormatter, Trogon.Test.ReportFormatter],
        trogon_test_report: [path: "tmp/test-report.txt", include_logs: false]
      )

    * `:path` - where the report is written, relative to the directory
      `mix test` runs in. Defaults to `"test-report.txt"`. The file is
      replaced on every run.

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
    path |> Path.dirname() |> File.mkdir_p!()

    {:ok, %__MODULE__{device: File.open!(path, [:write, :utf8]), include_logs: include_logs, tally: %Tally{}}}
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
    File.close(state.device)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp options!(opts) do
    opts = Keyword.validate!(opts, path: "test-report.txt", include_logs: true)

    case {opts[:path], opts[:include_logs]} do
      {path, include_logs} when is_binary(path) and is_boolean(include_logs) ->
        {path, include_logs}

      _invalid ->
        raise ArgumentError,
              "expected :path to be a string and :include_logs a boolean, got: #{inspect(opts)}"
    end
  end

  defp write(_state, nil), do: :ok
  defp write(state, iodata), do: IO.write(state.device, iodata)
end
