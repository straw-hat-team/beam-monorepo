defmodule Trogon.Credo.PluginCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Credo.CLI.Output.Shell
  alias Credo.Execution

  using do
    quote do
      import Trogon.Credo.PluginCase
    end
  end

  # Runs Credo end to end, the way `mix credo` does, against the given sources
  # with the given `.credo.exs` contents, and returns the issues it reports. The
  # config is passed with `--config-file`, so no `.credo.exs` above the temporary
  # directory takes part. `{dir}` in the config is replaced with that directory.
  def run_credo(config, sources, argv \\ []) do
    dir = Path.join(System.tmp_dir!(), "trogon_credo_plugin_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    try do
      config_file = Path.join(dir, ".credo.exs")
      File.write!(config_file, String.replace(config, "{dir}", dir))

      for {name, source} <- sources, do: File.write!(Path.join(dir, name), source)

      argv = ["--config-file", config_file, "--mute-exit-status", "--strict"] ++ argv ++ [dir]
      Shell.suppress_output(fn -> send(self(), {:credo_result, run(argv)}) end)

      receive do
        {:credo_result, {:ok, exec}} -> exec |> Execution.get_issues() |> Enum.sort_by(&{&1.line_no, &1.check})
        {:credo_result, {:error, error, stacktrace}} -> reraise error, stacktrace
      end
    after
      File.rm_rf!(dir)
    end
  end

  # A raise is carried out of the callback, so Credo's output is turned back on
  # before the test sees it.
  defp run(argv) do
    {:ok, Credo.run(argv)}
  rescue
    error -> {:error, error, __STACKTRACE__}
  end

  # A `.credo.exs` that runs only the given plugins and checks, so an issue from
  # Credo's own default checks never shows up in a plugin test.
  def config(plugins, checks \\ "%{enabled: []}", name \\ "default") do
    """
    %{
      configs: [
        %{
          name: #{inspect(name)},
          files: %{included: ["{dir}"]},
          plugins: #{inspect(plugins, limit: :infinity)},
          checks: #{checks}
        }
      ]
    }
    """
  end
end
