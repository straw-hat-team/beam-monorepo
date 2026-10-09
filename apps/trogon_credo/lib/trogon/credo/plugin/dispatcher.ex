defmodule Trogon.Credo.Plugin.Dispatcher do
  @moduledoc """
  A Credo plugin that enables the checks under `Trogon.Credo.Check.Dispatcher`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Dispatcher, []}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Dispatcher.ContextMutation`

  ## Params

    * `middleware_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation`. Left out, the check's own
      default applies.
    * `handler_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation`. Left out, the check's own
      default applies.
    * `context_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation`. Left out, the check's own
      default applies.
    * `except_in` - forwarded to `Trogon.Credo.Check.Dispatcher.ContextMutation`.
      Left out, the check's own default applies.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so
  `{Trogon.Credo.Check.Dispatcher.ContextMutation, false}` disables it as well.
  The plugin adds its checks after Credo has merged every config file, so this
  holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.Dispatcher.ContextMutation
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {ContextMutation,
       PluginSupport.check_params(exec, __MODULE__, [
         :middleware_modules,
         :handler_modules,
         :context_modules,
         :except_in
       ])}
    ])
  end
end
