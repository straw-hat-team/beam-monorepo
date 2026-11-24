defmodule Trogon.Credo.Plugin.Default do
  @moduledoc """
  A Credo plugin that enables the general checks, the ones that apply to any Elixir
  project and work with their defaults.

  The other plugins under `Trogon.Credo.Plugin` each cover one library, such as Ecto,
  Oban, Commanded, Dispatcher, OpenTelemetry, or ExUnit. This one covers no library.
  New general checks join it rather than getting a plugin of their own.

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Default, []}]
          }
        ]
      }

  It enables:

    * `Trogon.Credo.Check.Warning.SystemEnvRead`
    * `Trogon.Credo.Check.ExUnit.ApplicationEnvMutation`
    * `Trogon.Credo.Check.Warning.RaiseString`
    * `Trogon.Credo.Check.Readability.OneModulePerFile`

  ## Which checks join

  A check joins this plugin when it applies to any Elixir project and works without
  project-specific params. A check that needs params to mean anything, such as
  `Trogon.Credo.Check.Readability.ModuleNameMatchesPath` with its root or
  `Trogon.Credo.Check.Design.NamespaceBoundary`, stays out, and so does a check that
  covers one library.

  ## Params

    * `except` - a list of the checks above to leave disabled.

  The plugin does not forward per-check params, since each check gives `hint` its own
  meaning. To change a check's params, list that check in the project's own `checks:`.
  That entry replaces the one this plugin adds, params and all:

      %{
        configs: [
          %{
            name: "default",
            plugins: [{Trogon.Credo.Plugin.Default, []}],
            checks: %{
              extra: [
                {Trogon.Credo.Check.Warning.SystemEnvRead,
                 [
                   allowed_files: [
                     {"test/support/postgres.ex", "Gates the Postgres tests on a database URL."}
                   ],
                   hint: "Read it with Application.fetch_env!/2 and set it in config/runtime.exs."
                 ]}
              ]
            }
          }
        ]
      }

  A check the project configures in its own `.credo.exs` keeps that entry, params
  and all, instead of the one this plugin adds, so
  `{Trogon.Credo.Check.Warning.SystemEnvRead, false}` disables it as well.
  The plugin adds its checks after Credo has merged every config file, so this
  holds whether the project writes `checks: %{enabled: [...]}`,
  `checks: %{extra: [...]}`, or a plain list, and whichever config `--config-name`
  selects.
  """

  alias Trogon.Credo.Check.ExUnit.ApplicationEnvMutation
  alias Trogon.Credo.Check.Readability.OneModulePerFile
  alias Trogon.Credo.Check.Warning.RaiseString
  alias Trogon.Credo.Check.Warning.SystemEnvRead
  alias Trogon.Credo.PluginSupport

  @doc false
  def init(exec) do
    PluginSupport.enable_checks(exec, __MODULE__, [
      {SystemEnvRead, []},
      {ApplicationEnvMutation, []},
      {RaiseString, []},
      {OneModulePerFile, []}
    ])
  end
end
