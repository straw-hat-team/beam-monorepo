defmodule Trogon.Credo.Plugin.Oban do
  @moduledoc """
  A Credo plugin that enables the checks under `Trogon.Credo.Check.Oban`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Oban, [workers: [Oban.Pro.Worker, MyApp.Worker]]}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Oban.WorkerQueue`
    * `Trogon.Credo.Check.Oban.WorkerName`
    * `Trogon.Credo.Check.Oban.ForbiddenDecorator`

  ## Params

    * `workers` - forwarded as `for_use` to `Trogon.Credo.Check.Oban.WorkerQueue`
      and `Trogon.Credo.Check.Oban.WorkerName`. Left out, each check's own default
      applies.
    * `suffixes` - forwarded to `Trogon.Credo.Check.Oban.WorkerName`.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so `{Trogon.Credo.Check.Oban.WorkerName,
  false}` disables it as well. The plugin adds its checks after Credo has merged every
  config file, so this holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.Oban.ForbiddenDecorator
  alias Trogon.Credo.Check.Oban.WorkerName
  alias Trogon.Credo.Check.Oban.WorkerQueue
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {WorkerQueue, PluginSupport.check_params(exec, __MODULE__, workers: :for_use)},
      {WorkerName, PluginSupport.check_params(exec, __MODULE__, [{:workers, :for_use}, :suffixes])},
      {ForbiddenDecorator, []}
    ])
  end
end
