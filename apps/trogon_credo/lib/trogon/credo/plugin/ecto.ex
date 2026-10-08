defmodule Trogon.Credo.Plugin.Ecto do
  @moduledoc """
  A Credo plugin that enables the checks under `Trogon.Credo.Check.Ecto`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Ecto, [repos: [MyApp.Repo]]}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Ecto.RepoTransact`

  ## Params

    * `repos` - forwarded to `Trogon.Credo.Check.Ecto.RepoTransact`. Left out, the
      check's own default applies.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so `{Trogon.Credo.Check.Ecto.RepoTransact,
  false}` disables it as well. The plugin adds its checks after Credo has merged every
  config file, so this holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.Ecto.RepoTransact
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {RepoTransact, PluginSupport.check_params(exec, __MODULE__, [:repos])}
    ])
  end
end
