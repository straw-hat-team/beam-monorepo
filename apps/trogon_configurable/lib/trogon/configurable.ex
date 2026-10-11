defmodule Trogon.Configurable do
  @options_schema NimbleOptions.new!(
                    otp_app: [
                      type: :atom,
                      doc: "The OTP app whose environment holds the configuration, under the module's name."
                    ],
                    config: [
                      type: :keyword_list,
                      default: [],
                      doc: "The static configuration."
                    ]
                  )

  @moduledoc """
  Defines a configurable module. A configurable module exposes a `get_config/1`
  function that returns its configuration, merged from three sources, where
  each one overrides the one before it:

  * The macro options, most likely used for static values.
  * The `Config` of the OTP app, most likely used for environment-based values.
  * The `get_config/1` parameters, most likely used when you want to control
    the values at runtime.

  The options are checked when the configurable module compiles, so a misspelled
  or unknown option fails the build instead of being ignored.

  ## Options

  #{NimbleOptions.docs(@options_schema)}

  ### Static Configuration

  When you need default values that require neither runtime execution nor the
  environment. The options are evaluated once, when the module compiles, so
  module attributes work and a call such as `System.get_env/1` reads the
  machine that compiles the module, not the one that runs it.

      defmodule MyConfigurableModule do
        use Trogon.Configurable,
          config: [
            site: "https://myproductionsite.com"
          ]
      end

  ### Environment Configuration

  When you pass the `otp_app`, the configuration is looked up by the OTP app
  name and the module name.

      defmodule MyConfigurableModule do
        use Trogon.Configurable, otp_app: :my_app
      end

  Then you can configure the values in your config files.

      config :my_app, MyConfigurableModule,
        some_value_here: ""

  This allows you to swap values based on the environment.

  ### Runtime Configuration

  Since your module defines `get_config/1`, you can always call it with extra
  configuration.

      MyConfigurableModule.get_config(another_value: "")

  ### Testing

  The environment is read through `Application`, which the test environment
  can swap for `Trogon.Test.MockApplication` in `config/test.exs`:

      config :trogon_configurable, Trogon.Configurable,
        application: Trogon.Test.MockApplication

  To swap it for a single configurable module, configure that module instead,
  which takes precedence over the setting above:

      config :trogon_configurable, MyConfigurableModule,
        application: Trogon.Test.MockApplication

  Both settings are read when the configurable module compiles, so neither
  costs anything at runtime.

  A test then expects the read instead of writing the environment with
  `Application.put_env/3`, so it stays `async: true`:

      TestApplication.expect_get_env(returns: [site: "https://staging.example"])

      assert MyConfigurableModule.get_config()[:site] == "https://staging.example"
      TestApplication.assert_received_get_env(:my_app, MyConfigurableModule, [])
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      options = Trogon.Configurable.validate_options!(opts)

      application =
        Application.compile_env(
          :trogon_configurable,
          [__MODULE__, :application],
          Application.compile_env(:trogon_configurable, [Trogon.Configurable, :application], Application)
        )

      @doc """
      Returns the configuration for `#{inspect(__MODULE__)}`.
      """
      @spec get_config(keyword()) :: keyword()
      def get_config(params \\ []) do
        Trogon.Configurable.get_config(__MODULE__, unquote(application), unquote(Macro.escape(options)), params)
      end
    end
  end

  @doc false
  @spec validate_options!(keyword()) :: keyword()
  def validate_options!(opts), do: NimbleOptions.validate!(opts, @options_schema)

  @doc false
  @spec get_config(module(), module(), keyword(), keyword()) :: keyword()
  def get_config(module, application, opts, params) do
    opts
    |> Keyword.fetch!(:config)
    |> Keyword.merge(environment_config(module, application, opts))
    |> Keyword.merge(params)
  end

  defp environment_config(module, application, opts) do
    case Keyword.get(opts, :otp_app) do
      nil -> []
      otp_app -> application.get_env(otp_app, module, [])
    end
  end
end
