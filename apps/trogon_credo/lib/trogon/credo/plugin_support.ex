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
  #
  # `aliases` maps a check to the deprecated modules that used to be its name, so
  # `except`, and a project's own entry for the deprecated module, both reach the
  # check they actually mean.
  def enable_checks(exec, plugin, checks, aliases \\ %{}) do
    except = exec |> param(plugin, :except) |> List.wrap()
    validate_except!(plugin, except, checks, aliases)

    enabled = reject_listed(checks, except, aliases)

    Credo.Plugin.append_task(
      exec,
      :convert_cli_options_to_config,
      {Trogon.Credo.PluginSupport.EnableChecks, checks: enabled, aliases: aliases}
    )
  end

  def reject_listed(checks, listed, aliases \\ %{}) do
    Enum.reject(checks, &listed?(&1, listed, aliases))
  end

  defp listed?({check, _params}, listed, aliases) do
    check in listed or Enum.any?(Map.get(aliases, check, []), &(&1 in listed))
  end

  defp param(exec, plugin, name) do
    Execution.get_plugin_param(exec, plugin, name)
  end

  # Keeps only the params a project set, so a check's own default applies to
  # anything the plugin leaves out. A `{plugin_param, check_param}` pair forwards
  # a plugin param under the name the check gives it.
  def check_params(exec, plugin, names) do
    for name <- names,
        {plugin_param, check_param} = param_names(name),
        value = param(exec, plugin, plugin_param),
        value != nil,
        do: {check_param, value}
  end

  defp param_names({plugin_param, check_param}), do: {plugin_param, check_param}
  defp param_names(name), do: {name, name}

  defp validate_except!(plugin, except, checks, aliases) do
    known =
      checks
      |> Enum.map(&elem(&1, 0))
      |> Enum.flat_map(&[&1 | Map.get(aliases, &1, [])])

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
