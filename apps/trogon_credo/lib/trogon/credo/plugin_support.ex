defmodule Trogon.Credo.PluginSupport do
  @moduledoc false

  alias Credo.Execution

  # Schedules the given checks to be enabled once Credo has merged every config
  # file, and drops the ones the plugin's `except` param names.
  #
  # `Credo.Plugin.register_default_config/2` is not used, since a config file
  # registered that way is merged before the project's own `.credo.exs`: a project
  # writing `checks: %{enabled: [...]}` replaces it, and a project selecting a
  # config with `--config-name` never loads it, since it is registered under one
  # name. Enabling the checks after the final merge instead adds each one the
  # project has not configured itself, whichever form its `.credo.exs` takes, while
  # a check the project does configure, or disables, keeps the project's entry.
  def enable_checks(exec, plugin, checks) do
    except = exec |> param(plugin, :except) |> List.wrap()
    validate_except!(plugin, except, checks)

    enabled = reject_listed(checks, except)

    Credo.Plugin.append_task(
      exec,
      :convert_cli_options_to_config,
      {Trogon.Credo.PluginSupport.EnableChecks, checks: enabled}
    )
  end

  def reject_listed(checks, listed) do
    Enum.reject(checks, &listed?(&1, listed))
  end

  defp listed?({check, _params}, listed), do: check in listed

  def param(exec, plugin, name) do
    Execution.get_plugin_param(exec, plugin, name)
  end

  # Keeps only the params a project set, so a check's own default applies to
  # anything the plugin leaves out.
  def check_params(exec, plugin, names) do
    for name <- names, value = param(exec, plugin, name), value != nil, do: {name, value}
  end

  defp validate_except!(plugin, except, checks) do
    known = Enum.map(checks, &elem(&1, 0))

    case Enum.reject(except, &Enum.member?(known, &1)) do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "invalid except #{inspect(unknown)} for #{inspect(plugin)}: expected checks the plugin enables, " <>
                "one of: #{inspect(known)}"
    end
  end
end
