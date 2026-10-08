defmodule Trogon.Credo.Plugin.OpenTelemetry do
  @moduledoc """
  A Credo plugin that enables the checks under `Trogon.Credo.Check.OpenTelemetry`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.OpenTelemetry, [task: MyApp.Task]}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.OpenTelemetry.TaskPropagation`

  ## Params

    * `task` - forwarded to `Trogon.Credo.Check.OpenTelemetry.TaskPropagation`.
      Left out, the check's own default applies.
    * `task_supervisor` - forwarded to
      `Trogon.Credo.Check.OpenTelemetry.TaskPropagation`. Left out, the check's own
      default applies.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so
  `{Trogon.Credo.Check.OpenTelemetry.TaskPropagation, false}` disables it as well.
  The plugin adds its checks after Credo has merged every config file, so this
  holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.

  A project that already enables
  `Trogon.Credo.Check.Warning.OpentelemetryTaskPropagation` drops that entry when it
  adds this plugin, so a call is not reported twice.
  """

  alias Trogon.Credo.Check.OpenTelemetry.TaskPropagation
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {TaskPropagation, PluginSupport.check_params(exec, __MODULE__, [:task, :task_supervisor])}
    ])
  end
end
