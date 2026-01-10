defmodule Trogon.Commanded.EventHandler do
  @moduledoc """
  Defines "Event Handler" modules that process events from the event store.

  This module wraps `Commanded.Event.Handler` with additional validation to ensure
  event handler names are properly configured.

  ## Configuration

  Configure the validator in your application config:

      # config/config.exs
      config :my_app, MyApp,
        event_handler_name_validator: MyApp.EventHandlerNameValidator

  And expose `otp_app` from your application module:

      defmodule MyApp do
        use Commanded.Application, otp_app: :my_app, ...

        # Expose otp_app for EventHandler to read
        def __otp_app__, do: @otp_app
      end

  ## Usage

      defmodule MyEventHandler do
        use Trogon.Commanded.EventHandler,
          application: MyApp,
          name: :MY_EVENT_HANDLER

        @impl Commanded.Event.Handler
        def handle(%MyEvent{} = event, metadata) do
          :ok
        end
      end
  """

  @doc """
  Validates and returns the processor name.

  This callback is invoked at compile time to:
  1. Validate that the given name is acceptable (raise `ArgumentError` if invalid)
  2. Return the processor name as a string

  ## Example

      @impl Trogon.Commanded.EventHandler
      def get_processor_name!(name) do
        # Validate name is in your enum
        MyApp.EventHandlerName.value(name)

        # Reject unspecified values
        if name == :EVENT_HANDLER_NAME_UNSPECIFIED do
          raise ArgumentError, "name cannot be :EVENT_HANDLER_NAME_UNSPECIFIED"
        end

        # Return the processor name
        Atom.to_string(name)
      end
  """
  @callback get_processor_name!(name :: atom()) :: String.t()

  @doc """
  Validates and returns the processor name from the validator.

  Ensures the validator returns a string, raising `ArgumentError` otherwise.
  """
  @spec validate_and_get_processor_name!(validator :: module(), name :: atom()) :: String.t()
  def validate_and_get_processor_name!(validator, name) do
    case validator.get_processor_name!(name) do
      result when is_binary(result) ->
        result

      other ->
        raise ArgumentError,
              "#{inspect(validator)}.get_processor_name!/1 must return a string, got: #{inspect(other)}"
    end
  end

  @doc """
  Resolves the OTP app from options or from the application module.
  """
  @spec resolve_otp_app!(application :: module(), opts :: keyword()) :: atom()
  def resolve_otp_app!(application, opts) do
    case Keyword.get(opts, :otp_app) do
      nil ->
        if function_exported?(application, :__otp_app__, 0) do
          application.__otp_app__()
        else
          raise ArgumentError, """
          Could not determine :otp_app for event handler.

          Either pass :otp_app option:

              use Trogon.Commanded.EventHandler,
                application: #{inspect(application)},
                otp_app: :my_app,
                name: :MY_HANDLER

          Or add __otp_app__/0 to your application module:

              defmodule #{inspect(application)} do
                use Commanded.Application, otp_app: :my_app, ...

                def __otp_app__, do: @otp_app
              end

          """
        end

      otp_app ->
        otp_app
    end
  end

  @doc """
  Converts the module into a `Commanded.Event.Handler`.

  This macro wraps `Commanded.Event.Handler` with additional validation to ensure
  the event handler name is valid according to the configured validator module.

  ## Required Options

  - `:application` - The Commanded application module.
  - `:name` - The name of the processor (an atom).

  ## Optional Options

  - `:otp_app` - The OTP application name for compile_env lookup.
    If not provided, reads from `application.__otp_app__()`.

  All other options from `Commanded.Event.Handler` are supported:
  - `:consistency` - Defines the consistency guarantee for the event handler.
  - `:subscribe_to` - Subscribe to a single stream or all streams.
  - `:start_from` - Choose which events to receive.

  ## Configuration

  Configure the validator in your application config:

      # config/config.exs
      config :my_app, MyApp,
        event_handler_name_validator: MyApp.EventHandlerNameValidator

  And expose `otp_app` from your application module:

      defmodule MyApp do
        use Commanded.Application, otp_app: :my_app, ...

        def __otp_app__, do: @otp_app
      end

  ## Validator Module

  Create a validator module that implements the behaviour:

      defmodule MyApp.EventHandlerNameValidator do
        @behaviour Trogon.Commanded.EventHandler

        @impl Trogon.Commanded.EventHandler
        def get_processor_name!(name) do
          # Validate name is in your enum
          MyApp.EventHandlerName.value(name)

          # Reject unspecified values
          if name == :EVENT_HANDLER_NAME_UNSPECIFIED do
            raise ArgumentError, "name cannot be :EVENT_HANDLER_NAME_UNSPECIFIED"
          end

          Atom.to_string(name)
        end
      end

  ## Usage

      defmodule MyEventHandler do
        use Trogon.Commanded.EventHandler,
          application: MyApp,
          name: :MY_EVENT_HANDLER

        @impl Commanded.Event.Handler
        def handle(%MyEvent{} = event, metadata) do
          # Handle the event
          :ok
        end
      end

  ## Why Use a Validator?

  Using a validator module for event handler names provides:

  1. **Type Safety**: Compile-time validation that the name is valid.
  2. **Consistency**: All handler names are validated against a single source of truth.
  3. **Refactoring Safety**: Changing valid names will cause compile-time errors.
  4. **Flexibility**: Each project can define its own validation rules.
  """
  @spec __using__(opts :: keyword()) :: Macro.t()
  defmacro __using__(opts) do
    application = opts |> Keyword.fetch!(:application) |> Macro.expand(__CALLER__)
    otp_app = __MODULE__.resolve_otp_app!(application, opts)
    name = Keyword.fetch!(opts, :name)
    commanded_opts = Keyword.delete(opts, :otp_app)

    quote do
      @__processor_name__ Trogon.Commanded.EventHandler.validate_and_get_processor_name!(
                            Application.compile_env!(
                              unquote(otp_app),
                              [unquote(application), :event_handler_name_validator]
                            ),
                            unquote(name)
                          )

      use Commanded.Event.Handler, Keyword.put(unquote(commanded_opts), :name, @__processor_name__)
    end
  end
end
