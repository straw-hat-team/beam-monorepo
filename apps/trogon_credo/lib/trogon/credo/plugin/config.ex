defmodule Trogon.Credo.Plugin.Config do
  @moduledoc """
  A Credo plugin that enables the checks under `Trogon.Credo.Check.Config`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Config, []}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Config.SystemEnvRead`

  ## Params

    * `calls` - forwarded to `Trogon.Credo.Check.Config.SystemEnvRead`.
      Left out, the check's own default applies.
    * `hint` - forwarded to `Trogon.Credo.Check.Config.SystemEnvRead`.
      Left out, the check's own default applies.
    * `allowed_files` - forwarded to `Trogon.Credo.Check.Config.SystemEnvRead`.
      Left out, the check's own default applies.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so
  `{Trogon.Credo.Check.Config.SystemEnvRead, false}` disables it as well.
  The plugin adds its checks after Credo has merged every config file, so this
  holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.Config.SystemEnvRead
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {SystemEnvRead, PluginSupport.check_params(exec, __MODULE__, [:calls, :hint, :allowed_files])}
    ])
  end
end
