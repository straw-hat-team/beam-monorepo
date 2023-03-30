defmodule OnePiece.Configurable do
  @moduledoc """
  It defines a configurable module. A configurable module expose `config`
  function that returns the configuration of the module based a merge strategy.

  The configuration will use three configurations:

  * Using the macro parameters, most likely used for static values.
  * Using `Config` module, most likely used for environment-based values.
  * Runtime based on the parameters, most likely used when you want to control
  the values at runtime.

  ### Static Configuration

  When you need to define default values that do not require runtime execution
  nor they are based on the environment. They are most likely static values.

      defmodule MyConfigurableModule do
        use OnePiece.Configurable,
          config: [
            site: "https://myproductionsite.com"
          ]
      end

  ### Environment Configuration

  When you pass the `otp_app`, we will lookup based on the OTP app name and the
  module name.

      defmodule MyConfigurableModule do
        use OnePiece.Configurable, otp_app: :my_app
      end

  Then you can configure the values in your config files.

      config :my_app, MyConfigurableModule,
        some_value_here: ""

  This will allow you to swap values based on the environment.

  ### Runtime Configuration

  Since your module will contain the `config` function, you can always call it
  with extra configs.

      MyConfigurableModule.get_config([
        another_value: ""
      ])
  """

  defmacro __using__(opts) do
    quote do
      @doc """
      Returns the configuration for #{__MODULE__}.
      """
      @spec get_config(keyword()) :: keyword()
      def get_config(params \\ []) do
        OnePiece.Configurable.get_config(__MODULE__, unquote(opts), params)
      end
    end
  end

  @doc false
  def get_config(module, opts, params) do
    default_config = Keyword.get(opts, :config, [])

    default_config
    |> Keyword.merge(environment_config(module, opts))
    |> Keyword.merge(params)
  end

  defp environment_config(module, opts) do
    case Keyword.get(opts, :otp_app) do
      nil -> []
      otp_app -> Application.get_env(otp_app, module, [])
    end
  end
end
