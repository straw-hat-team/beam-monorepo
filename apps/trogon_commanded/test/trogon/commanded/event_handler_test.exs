defmodule Trogon.Commanded.EventHandlerTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.EventHandler

  # A mock enum module that simulates protobuf enum behavior
  defmodule EventHandlerName do
    @moduledoc false

    @values %{
      EVENT_HANDLER_NAME_UNSPECIFIED: 0,
      MY_PROCESSOR: 1,
      ANOTHER_PROCESSOR: 2
    }

    def value(name) when is_map_key(@values, name) do
      Map.fetch!(@values, name)
    end
  end

  # A validator module that implements the behaviour
  defmodule EventHandlerNameValidator do
    @moduledoc false
    @behaviour Trogon.Commanded.EventHandler

    @impl Trogon.Commanded.EventHandler
    def get_processor_name!(name) do
      try do
        EventHandlerName.value(name)
      rescue
        FunctionClauseError ->
          reraise ArgumentError,
                  "name must be a valid EventHandlerName, got: #{inspect(name)}",
                  __STACKTRACE__
      end

      name_string = Atom.to_string(name)

      if String.ends_with?(name_string, "_UNSPECIFIED") do
        raise ArgumentError, "name cannot be an UNSPECIFIED value, got: #{inspect(name)}"
      end

      name_string
    end
  end

  # A validator with custom processor name format
  defmodule CustomNameValidator do
    @moduledoc false
    @behaviour Trogon.Commanded.EventHandler

    @impl Trogon.Commanded.EventHandler
    def get_processor_name!(:CUSTOM_NAME), do: "custom-processor-name"
  end

  describe "get_processor_name!/1 callback" do
    test "returns the name as a string when valid" do
      assert EventHandlerNameValidator.get_processor_name!(:MY_PROCESSOR) == "MY_PROCESSOR"
    end

    test "raises ArgumentError when name is not a valid enum value" do
      assert_raise ArgumentError,
                   ~r/name must be a valid EventHandlerName.*got: :INVALID_NAME/,
                   fn ->
                     EventHandlerNameValidator.get_processor_name!(:INVALID_NAME)
                   end
    end

    test "raises ArgumentError when name is an UNSPECIFIED value" do
      assert_raise ArgumentError, ~r/name cannot be an UNSPECIFIED value/, fn ->
        EventHandlerNameValidator.get_processor_name!(:EVENT_HANDLER_NAME_UNSPECIFIED)
      end
    end

    test "can return custom processor name format" do
      assert CustomNameValidator.get_processor_name!(:CUSTOM_NAME) == "custom-processor-name"
    end
  end

  describe "resolve_otp_app!/2" do
    test "returns otp_app from options when provided" do
      assert EventHandler.resolve_otp_app!(SomeApp, otp_app: :my_app) == :my_app
    end

    test "reads otp_app from application module when not in options" do
      defmodule AppWithOtpApp do
        def __otp_app__, do: :test_app
      end

      assert EventHandler.resolve_otp_app!(AppWithOtpApp, []) == :test_app
    end

    test "raises when otp_app not provided and application doesn't expose it" do
      defmodule AppWithoutOtpApp do
      end

      assert_raise ArgumentError, ~r/Could not determine :otp_app/, fn ->
        EventHandler.resolve_otp_app!(AppWithoutOtpApp, [])
      end
    end
  end

  # A validator that returns wrong type (for testing validation)
  defmodule BadReturnValidator do
    @moduledoc false
    @behaviour Trogon.Commanded.EventHandler

    @impl Trogon.Commanded.EventHandler
    def get_processor_name!(_name), do: :not_a_string
  end

  # Configure the test app for compile_env! to work
  Application.put_env(:trogon_commanded, TestSupport.DefaultApp,
    event_handler_name_validator: EventHandlerNameValidator
  )

  Application.put_env(:trogon_commanded, __MODULE__.CustomApp,
    event_handler_name_validator: CustomNameValidator
  )

  Application.put_env(:trogon_commanded, __MODULE__.AppWithOtpAppFunction,
    event_handler_name_validator: EventHandlerNameValidator
  )

  Application.put_env(:trogon_commanded, __MODULE__.BadReturnApp,
    event_handler_name_validator: BadReturnValidator
  )

  defmodule CustomApp do
    @moduledoc false
  end

  defmodule AppWithOtpAppFunction do
    @moduledoc false
    def __otp_app__, do: :trogon_commanded
  end

  defmodule BadReturnApp do
    @moduledoc false
  end

  describe "__using__/1" do
    test "defines a valid event handler with explicit otp_app" do
      defmodule ValidEventHandlerExplicit do
        use Trogon.Commanded.EventHandler,
          application: TestSupport.DefaultApp,
          otp_app: :trogon_commanded,
          name: :MY_PROCESSOR

        @impl Commanded.Event.Handler
        def handle(_event, _metadata) do
          :ok
        end
      end

      assert Code.ensure_compiled!(ValidEventHandlerExplicit)
      assert function_exported?(ValidEventHandlerExplicit, :handle, 2)
    end

    test "defines a valid event handler reading otp_app from application" do
      defmodule ValidEventHandlerImplicit do
        use Trogon.Commanded.EventHandler,
          application: AppWithOtpAppFunction,
          name: :MY_PROCESSOR

        @impl Commanded.Event.Handler
        def handle(_event, _metadata) do
          :ok
        end
      end

      assert Code.ensure_compiled!(ValidEventHandlerImplicit)
      assert function_exported?(ValidEventHandlerImplicit, :handle, 2)
    end

    test "uses custom processor name from validator" do
      defmodule CustomNameEventHandler do
        use Trogon.Commanded.EventHandler,
          application: CustomApp,
          otp_app: :trogon_commanded,
          name: :CUSTOM_NAME

        @impl Commanded.Event.Handler
        def handle(_event, _metadata) do
          :ok
        end
      end

      assert Code.ensure_compiled!(CustomNameEventHandler)
    end

    test "raises when name is not valid at compile time" do
      assert_raise ArgumentError, ~r/name must be a valid/, fn ->
        defmodule InvalidEventHandler do
          use Trogon.Commanded.EventHandler,
            application: TestSupport.DefaultApp,
            otp_app: :trogon_commanded,
            name: :INVALID
        end
      end
    end

    test "raises when name is UNSPECIFIED at compile time" do
      assert_raise ArgumentError, ~r/name cannot be an UNSPECIFIED value/, fn ->
        defmodule UnspecifiedEventHandler do
          use Trogon.Commanded.EventHandler,
            application: TestSupport.DefaultApp,
            otp_app: :trogon_commanded,
            name: :EVENT_HANDLER_NAME_UNSPECIFIED
        end
      end
    end

    test "raises when config is not set" do
      assert_raise ArgumentError, ~r/could not fetch application environment/, fn ->
        defmodule NoConfigEventHandler do
          use Trogon.Commanded.EventHandler,
            application: SomeUnconfiguredApp,
            otp_app: :nonexistent_app,
            name: :MY_PROCESSOR
        end
      end
    end

    test "raises when otp_app not provided and application doesn't expose it" do
      defmodule AppWithoutOtpAppForMacro do
      end

      assert_raise ArgumentError, ~r/Could not determine :otp_app/, fn ->
        defmodule NoOtpAppEventHandler do
          use Trogon.Commanded.EventHandler,
            application: AppWithoutOtpAppForMacro,
            name: :MY_PROCESSOR
        end
      end
    end

    test "raises when validator returns non-string" do
      assert_raise ArgumentError, ~r/must return a string, got: :not_a_string/, fn ->
        defmodule BadReturnEventHandler do
          use Trogon.Commanded.EventHandler,
            application: BadReturnApp,
            otp_app: :trogon_commanded,
            name: :SOME_NAME
        end
      end
    end
  end
end
