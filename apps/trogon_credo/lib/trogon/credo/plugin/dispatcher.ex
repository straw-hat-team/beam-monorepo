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
    * `Trogon.Credo.Check.Dispatcher.StructConstruction`
    * `Trogon.Credo.Check.Dispatcher.PrivateOwnership`
    * `Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys`

  ## Params

    * `middleware_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation` and
      `Trogon.Credo.Check.Dispatcher.PrivateOwnership`. Left out, each check's own
      default applies.
    * `handler_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation`. Left out, the check's own
      default applies.
    * `context_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.ContextMutation`,
      `Trogon.Credo.Check.Dispatcher.StructConstruction` and
      `Trogon.Credo.Check.Dispatcher.PrivateOwnership`. Left out, each check's own
      default applies.
    * `dispatch_options_modules` - forwarded to
      `Trogon.Credo.Check.Dispatcher.StructConstruction` and
      `Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys`. Left out, each check's
      own default applies.
    * `except_in` - forwarded to every check above. Left out, each check's own
      default applies.
    * `hint` - forwarded to every check above. Left out, each check's own default
      applies.
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
  alias Trogon.Credo.Check.Dispatcher.DispatchOptionsKeys
  alias Trogon.Credo.Check.Dispatcher.PrivateOwnership
  alias Trogon.Credo.Check.Dispatcher.StructConstruction
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {ContextMutation,
       PluginSupport.check_params(exec, __MODULE__, [
         :middleware_modules,
         :handler_modules,
         :context_modules,
         :except_in,
         :hint
       ])},
      {StructConstruction,
       PluginSupport.check_params(exec, __MODULE__, [
         :dispatch_options_modules,
         :context_modules,
         :except_in,
         :hint
       ])},
      {PrivateOwnership,
       PluginSupport.check_params(exec, __MODULE__, [
         :middleware_modules,
         :context_modules,
         :except_in,
         :hint
       ])},
      {DispatchOptionsKeys,
       PluginSupport.check_params(exec, __MODULE__, [
         :dispatch_options_modules,
         :except_in,
         :hint
       ])}
    ])
  end
end
