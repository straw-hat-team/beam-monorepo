defmodule Trogon.ExUnitReporter do
  @moduledoc """
  An ExUnit formatter that writes a token-optimized test report to a file.

  Designed for AI coding agents. Passing tests produce zero output — only the
  summary line. Failed tests get compact but complete diagnostic blocks with
  assertion details, diffs, and trimmed stacktraces.

  Runs alongside the default CLI formatter: humans see normal terminal output,
  the agent reads the report file.

  ## Usage

  Add this formatter in your `test/test_helper.exs`:

      ExUnit.configure(
        formatters: [ExUnit.CLIFormatter, Trogon.ExUnitReporter]
      )

      ExUnit.start()

  ## Configuration

  Pass options under the `:trogon_exunit_reporter` key:

      ExUnit.configure(
        formatters: [ExUnit.CLIFormatter, Trogon.ExUnitReporter],
        trogon_exunit_reporter: [
          file_path: "test-report.txt",
          include_logs: true
        ]
      )

  See `Trogon.ExUnitReporter.Config` for all available options.
  """

  use GenServer

  alias Trogon.ExUnitReporter.Config
  alias Trogon.ExUnitReporter.Event

  defstruct [:config, :io_device, :counters]

  @type t :: %__MODULE__{
          config: Config.t(),
          io_device: File.io_device(),
          counters: map()
        }

  @impl GenServer
  def init(opts) do
    config = Config.from_exunit_opts!(opts)
    io_device = open_file(config.file_path)

    state = %__MODULE__{
      config: config,
      io_device: io_device,
      counters: %{total: 0, passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:suite_started, _opts}, state) do
    {:noreply, state}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    event_opts = [include_logs: state.config.include_logs]

    case Event.format_test(test, event_opts) do
      nil -> :ok
      iodata -> IO.write(state.io_device, [iodata, "\n"])
    end

    counters = update_counters(state.counters, test)
    {:noreply, %{state | counters: counters}}
  end

  def handle_cast({:suite_finished, times_us}, state) do
    IO.write(state.io_device, Event.format_summary(times_us, state.counters))
    File.close(state.io_device)
    {:noreply, state}
  end

  def handle_cast(:max_failures_reached, state) do
    IO.write(state.io_device, Event.format_max_failures_reached())
    {:noreply, state}
  end

  def handle_cast({:sigquit, _running}, state) do
    File.close(state.io_device)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  # -- Private --

  defp update_counters(counters, %ExUnit.Test{state: state}) do
    key =
      case state do
        nil -> :passed
        {:failed, _} -> :failed
        {:skipped, _} -> :skipped
        {:excluded, _} -> :excluded
        {:invalid, _} -> :invalid
      end

    counters
    |> Map.update!(:total, &(&1 + 1))
    |> Map.update!(key, &(&1 + 1))
  end

  defp open_file(path) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.open!(path, [:write, :utf8])
  end
end
