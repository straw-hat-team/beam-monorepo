defmodule Trogon.Credo.Plugin.Commanded do
  @moduledoc """
  A Credo plugin that enables the checks for projects built on
  `Trogon.Commanded`.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Commanded, [aggregate_modules: [MyApp.Aggregate]]}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Commanded.AggregateApplyCall`
    * `Trogon.Credo.Check.Commanded.DeterministicCommand`
    * `Trogon.Credo.Check.Commanded.SwappableNonDeterminism`
    * `Trogon.Credo.Check.Commanded.ErrorOwnership`

  ## Params

    * `aggregate_modules` - forwarded to
      `Trogon.Credo.Check.Commanded.AggregateApplyCall` and
      `Trogon.Credo.Check.Commanded.DeterministicCommand`. Left out, each check's own
      default applies.
    * `command_handler_modules` - forwarded to
      `Trogon.Credo.Check.Commanded.AggregateApplyCall` and
      `Trogon.Credo.Check.Commanded.DeterministicCommand`. Left out, each check's own
      default applies.
    * `command_modules` - forwarded to
      `Trogon.Credo.Check.Commanded.DeterministicCommand`. Left out, the check's own
      default applies.
    * `event_modules` - forwarded to
      `Trogon.Credo.Check.Commanded.DeterministicCommand`. Left out, the check's own
      default applies.
    * `command_handler_case` - forwarded to
      `Trogon.Credo.Check.Commanded.AggregateApplyCall`. Left out, the check's own
      default applies.
    * `processor_modules` - forwarded to
      `Trogon.Credo.Check.Commanded.SwappableNonDeterminism`. Left out, the check's
      own default applies.
    * `except` - a list of the checks above to leave disabled.

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so
  `{Trogon.Credo.Check.Commanded.AggregateApplyCall, false}` disables it as well.
  The plugin adds its checks after Credo has merged every config file, so this
  holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.Commanded.AggregateApplyCall
  alias Trogon.Credo.Check.Commanded.DeterministicCommand
  alias Trogon.Credo.Check.Commanded.ErrorOwnership
  alias Trogon.Credo.Check.Commanded.SwappableNonDeterminism
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {AggregateApplyCall,
       PluginSupport.check_params(exec, __MODULE__, [
         :aggregate_modules,
         :command_handler_modules,
         :command_handler_case
       ])},
      {DeterministicCommand,
       PluginSupport.check_params(exec, __MODULE__, [
         :aggregate_modules,
         :command_handler_modules,
         :command_modules,
         :event_modules
       ])},
      {SwappableNonDeterminism, PluginSupport.check_params(exec, __MODULE__, [:processor_modules])},
      {ErrorOwnership, PluginSupport.check_params(exec, __MODULE__, [])}
    ])
  end
end
