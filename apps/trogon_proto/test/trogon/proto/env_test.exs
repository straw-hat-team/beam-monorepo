defmodule Trogon.Proto.EnvTest do
  use ExUnit.Case, async: true

  alias Trogon.Proto.Env
  alias Trogon.Proto.TestSupport
  alias Trogon.Proto.TestSupport.AllTypesConfig
  alias Trogon.Proto.TestSupport.ConfigWithEnum
  alias Trogon.Proto.TestSupport.ConfigWithRepeated
  alias Trogon.Proto.TestSupport.ConfigWithSteps
  alias Trogon.Proto.TestSupport.ConfigWithStepsDefault
  alias Trogon.Proto.TestSupport.ConfigWithStepsUrlSafe
  alias Trogon.Proto.TestSupport.ConfigWithTrimCustom
  alias Trogon.Proto.TestSupport.ConfigWithTrimUnicode
  alias Trogon.Proto.TestSupport.FutureSchema

  setup {Mox, :set_mox_from_context}

  # Unit tests for convert_field/2 - tests type conversion with proto atom types
  describe "convert_field/2" do
    test "converts :TYPE_STRING to string (passthrough)" do
      config = %{field_type: :TYPE_STRING, is_repeated: false, steps: []}

      assert Env.convert_field("hello world", config) == "hello world"
    end

    test "converts :TYPE_INT32 to integer" do
      config = %{field_type: :TYPE_INT32, is_repeated: false, steps: []}

      assert Env.convert_field("42", config) == 42
      assert Env.convert_field("-100", config) == -100
    end

    test "converts :TYPE_INT64 to integer" do
      config = %{field_type: :TYPE_INT64, is_repeated: false, steps: []}

      assert Env.convert_field("9223372036854775807", config) == 9_223_372_036_854_775_807
    end

    test "converts :TYPE_FLOAT to float" do
      config = %{field_type: :TYPE_FLOAT, is_repeated: false, steps: []}

      assert Env.convert_field("3.14", config) == 3.14
      assert Env.convert_field("42", config) == 42.0
    end

    test "converts :TYPE_DOUBLE to float" do
      config = %{field_type: :TYPE_DOUBLE, is_repeated: false, steps: []}

      assert Env.convert_field("2.718281828", config) == 2.718281828
    end

    test "converts :TYPE_BOOL truthy values to true" do
      config = %{field_type: :TYPE_BOOL, is_repeated: false, steps: []}

      assert Env.convert_field("true", config) == true
      assert Env.convert_field("TRUE", config) == true
      assert Env.convert_field("True", config) == true
      assert Env.convert_field("1", config) == true
      assert Env.convert_field("yes", config) == true
      assert Env.convert_field("YES", config) == true
      assert Env.convert_field("on", config) == true
      assert Env.convert_field("ON", config) == true
    end

    test "converts :TYPE_BOOL falsy values to false" do
      config = %{field_type: :TYPE_BOOL, is_repeated: false, steps: []}

      assert Env.convert_field("false", config) == false
      assert Env.convert_field("0", config) == false
      assert Env.convert_field("no", config) == false
      assert Env.convert_field("off", config) == false
      assert Env.convert_field("anything_else", config) == false
    end

    test "handles repeated :TYPE_STRING with split_delimiter" do
      config = %{field_type: :TYPE_STRING, is_repeated: true, steps: [{:split, ","}]}

      assert Env.convert_field("a,b,c", config) == ["a", "b", "c"]
    end

    test "handles repeated :TYPE_INT32 with split_delimiter" do
      config = %{field_type: :TYPE_INT32, is_repeated: true, steps: [{:split, ","}]}

      assert Env.convert_field("1,2,3", config) == [1, 2, 3]
    end

    test "handles repeated fields with unicode_whitespace trim" do
      config = %{
        field_type: :TYPE_STRING,
        is_repeated: true,
        steps: [{:split, ","}, {:trim, :unicode_whitespace}]
      }

      assert Env.convert_field("  a  ,  b  ,  c  ", config) == ["a", "b", "c"]
    end

    test "handles repeated fields with custom chars trim" do
      config = %{
        field_type: :TYPE_STRING,
        is_repeated: true,
        steps: [{:split, ","}, {:trim, {:chars, "*"}}]
      }

      assert Env.convert_field("*a*,*b*,*c*", config) == ["a", "b", "c"]
    end

    test "filters empty strings from repeated fields" do
      config = %{field_type: :TYPE_STRING, is_repeated: true, steps: [{:split, ","}]}

      assert Env.convert_field("a,,b,", config) == ["a", "b"]
    end

    test "raises ArgumentError for invalid float" do
      config = %{field_type: :TYPE_FLOAT, is_repeated: false, steps: []}

      error =
        assert_raise ArgumentError, fn ->
          Env.convert_field("not_a_number", config)
        end

      assert Exception.message(error) == ~s|not a valid float: "not_a_number"|
    end

    test "converts enum names to protobuf enum atoms" do
      config = %{field_type: {:enum, Acme.Test.V1.LogLevel}, is_repeated: false, steps: []}

      assert Env.convert_field("LOG_LEVEL_DEBUG", config) == :LOG_LEVEL_DEBUG
    end

    test "raises ArgumentError for invalid enum names" do
      config = %{field_type: {:enum, Acme.Test.V1.LogLevel}, is_repeated: false, steps: []}

      error =
        assert_raise ArgumentError, fn ->
          Env.convert_field("debug", config)
        end

      assert Exception.message(error) ==
               ~s|not a valid enum name "debug" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN|
    end

    test "does not treat numeric strings as enum values" do
      config = %{field_type: {:enum, Acme.Test.V1.LogLevel}, is_repeated: false, steps: []}

      error =
        assert_raise ArgumentError, fn ->
          Env.convert_field("1", config)
        end

      assert Exception.message(error) ==
               ~s|not a valid enum name "1" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN|
    end
  end

  describe "struct generation" do
    test "generates struct with all fields from environment" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "my-secret-key",
        "PORT" => "5432",
        "HOST" => "localhost",
        "TIMEOUT_MS" => "30000",
        "MAX_MEMORY_MB" => "512.5",
        "CPU_LIMIT" => "0.5",
        "DEBUG_MODE" => "true"
      })

      config = AllTypesConfig.from_env!()

      assert %AllTypesConfig{} = config
      assert config.env.database_url == "postgres://localhost"
      assert config.env.api_key == "my-secret-key"
      assert config.env.port == 5432
      assert config.env.host == "localhost"
      assert config.env.timeout_ms == 30_000
      assert config.env.max_memory_mb == 512.5
      assert config.env.cpu_limit == 0.5
      assert config.env.debug_mode == true
    end
  end

  describe "from_env/0 function" do
    test "returns {:ok, config} when every env var loads cleanly" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "my-secret-key",
        "PORT" => "5432",
        "HOST" => "localhost"
      })

      assert {:ok, %AllTypesConfig{} = config} = AllTypesConfig.from_env()
      assert config.env.database_url == "postgres://localhost"
      assert config.env.api_key == "my-secret-key"
      assert config.env.port == 5432
      assert config.env.host == "localhost"
    end

    test "returns {:error, LoadError} aggregating every failure" do
      TestSupport.stub_system_env(%{
        "MAX_MEMORY_MB" => "not_a_float",
        "PORT" => "not_an_int"
      })

      assert {:error, %Trogon.Proto.Env.LoadError{} = error} = AllTypesConfig.from_env()

      assert error.errors == [
               %{env_var: "PORT", field: :port, reason: {:invalid, "not a valid int32: \"not_an_int\""}},
               %{env_var: "API_KEY", field: :api_key, reason: :missing},
               %{env_var: "DATABASE_URL", field: :database_url, reason: :missing},
               %{
                 env_var: "MAX_MEMORY_MB",
                 field: :max_memory_mb,
                 reason: {:invalid, "not a valid float: \"not_a_float\""}
               }
             ]
    end

    test "does not raise on missing required env vars" do
      TestSupport.stub_system_env(%{})

      assert {:error, %Trogon.Proto.Env.LoadError{}} = AllTypesConfig.from_env()
    end
  end

  describe "from_env!/0 function" do
    test "loads required fields from environment" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "my-secret-key",
        "PORT" => "5432",
        "HOST" => "localhost"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.database_url == "postgres://localhost"
      assert config.env.api_key == "my-secret-key"
      assert config.env.port == 5432
      assert config.env.host == "localhost"
    end

    test "raises LoadError when DATABASE_URL is missing" do
      TestSupport.stub_system_env(%{
        "API_KEY" => "secret"
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          AllTypesConfig.from_env!()
        end

      assert [%{env_var: "DATABASE_URL", field: :database_url, reason: :missing}] = error.errors
    end

    test "raises LoadError when API_KEY is missing" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost"
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          AllTypesConfig.from_env!()
        end

      assert [%{env_var: "API_KEY", field: :api_key, reason: :missing}] = error.errors
    end

    test "aggregates every missing and invalid env var in a single error" do
      TestSupport.stub_system_env(%{
        "MAX_MEMORY_MB" => "not_a_float",
        "PORT" => "not_an_int"
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          AllTypesConfig.from_env!()
        end

      assert error.errors == [
               %{env_var: "PORT", field: :port, reason: {:invalid, "not a valid int32: \"not_an_int\""}},
               %{env_var: "API_KEY", field: :api_key, reason: :missing},
               %{env_var: "DATABASE_URL", field: :database_url, reason: :missing},
               %{
                 env_var: "MAX_MEMORY_MB",
                 field: :max_memory_mb,
                 reason: {:invalid, "not a valid float: \"not_a_float\""}
               }
             ]

      assert Exception.message(error) == """
             failed to load 4 environment variable(s):
               - PORT invalid (not a valid int32: "not_an_int")
               - API_KEY missing
               - DATABASE_URL missing
               - MAX_MEMORY_MB invalid (not a valid float: "not_a_float")
             """
    end

    test "applies default values for optional fields" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.port == 5432
      assert config.env.host == "localhost"
    end

    test "overrides default values with environment variables" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "PORT" => "8080",
        "HOST" => "example.com"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.port == 8080
      assert config.env.host == "example.com"
    end
  end

  describe "type conversion" do
    test "converts int32 fields from strings" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "PORT" => "8080"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.port == 8080
      assert is_integer(config.env.port)
    end

    test "converts int64 fields from strings" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "TIMEOUT_MS" => "5000"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.timeout_ms == 5000
      assert is_integer(config.env.timeout_ms)
    end

    test "converts float fields from strings" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "MAX_MEMORY_MB" => "256.5"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.max_memory_mb == 256.5
      assert is_float(config.env.max_memory_mb)
    end

    test "parses float and double from integer strings (e.g. MAX_MEMORY_MB=512)" do
      # String.to_float/1 raises on "512"; env vars are often set as integers
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "MAX_MEMORY_MB" => "512",
        "CPU_LIMIT" => "1"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.max_memory_mb == 512.0
      assert config.env.cpu_limit == 1.0
    end

    test "raises LoadError for invalid float value" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "MAX_MEMORY_MB" => "not_a_float"
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          AllTypesConfig.from_env!()
        end

      assert error.errors == [
               %{
                 env_var: "MAX_MEMORY_MB",
                 field: :max_memory_mb,
                 reason: {:invalid, ~s|not a valid float: "not_a_float"|}
               }
             ]

      assert Exception.message(error) == """
             failed to load 1 environment variable(s):
               - MAX_MEMORY_MB invalid (not a valid float: "not_a_float")
             """
    end

    test "converts double fields from strings" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "CPU_LIMIT" => "0.75"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.cpu_limit == 0.75
      assert is_float(config.env.cpu_limit)
    end

    test "converts bool fields from strings" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "DEBUG_MODE" => "true"
      })

      config = AllTypesConfig.from_env!()

      assert config.env.debug_mode == true
      assert is_boolean(config.env.debug_mode)
    end

    test "bool field handles various truthy values" do
      # Test multiple values separately with fresh mocks
      for value <- ["1", "yes", "on", "false"] do
        TestSupport.stub_system_env(%{
          "DATABASE_URL" => "postgres://localhost",
          "API_KEY" => "secret",
          "DEBUG_MODE" => value
        })

        config = AllTypesConfig.from_env!()
        expected = value != "false"
        assert config.env.debug_mode == expected
      end
    end

    test "applies defaults with correct types" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret"
      })

      config = AllTypesConfig.from_env!()

      # Verify defaults are applied as correct types
      assert config.env.port == 5432
      assert is_integer(config.env.port)

      assert config.env.timeout_ms == 30_000
      assert is_integer(config.env.timeout_ms)

      assert config.env.max_memory_mb == 512.5
      assert is_float(config.env.max_memory_mb)

      assert config.env.cpu_limit == 0.5
      assert is_float(config.env.cpu_limit)

      assert config.env.debug_mode == false
      assert is_boolean(config.env.debug_mode)
    end
  end

  describe "inspect protocol" do
    test "masks secret fields in inspect output" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "very-secret"
      })

      config = AllTypesConfig.from_env!()
      inspected = inspect(config)

      assert inspected ==
               "#Trogon.Proto.TestSupport.AllTypesConfig<port: 5432, host: \"localhost\", api_key: \"***SECRET***\", database_url: \"***SECRET***\", timeout_ms: 30000, max_memory_mb: 512.5, cpu_limit: 0.5, debug_mode: false>"
    end

    test "shows plaintext fields in inspect output" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "PORT" => "9000",
        "HOST" => "api.example.com"
      })

      config = AllTypesConfig.from_env!()
      inspected = inspect(config)

      assert inspected ==
               "#Trogon.Proto.TestSupport.AllTypesConfig<port: 9000, host: \"api.example.com\", api_key: \"***SECRET***\", database_url: \"***SECRET***\", timeout_ms: 30000, max_memory_mb: 512.5, cpu_limit: 0.5, debug_mode: false>"
    end

    test "safe for logging without exposing secrets" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://sensitive.db",
        "API_KEY" => "sk-very-sensitive-key"
      })

      config = AllTypesConfig.from_env!()
      log_output = "Config: #{inspect(config)}"

      assert log_output ==
               "Config: #Trogon.Proto.TestSupport.AllTypesConfig<port: 5432, host: \"localhost\", api_key: \"***SECRET***\", database_url: \"***SECRET***\", timeout_ms: 30000, max_memory_mb: 512.5, cpu_limit: 0.5, debug_mode: false>"
    end

    test "does not crash when config.env is nil" do
      # Struct created without load!/0 has env: nil; inspect used to raise
      config = %Trogon.Proto.TestSupport.AllTypesConfig{env: nil}

      result = inspect(config)

      assert result == "#Trogon.Proto.TestSupport.AllTypesConfig<nil>"
    end
  end

  describe "type specifications" do
    test "struct is of correct type" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret"
      })

      config = AllTypesConfig.from_env!()

      # Just verify it's a AllTypesConfig struct
      assert %AllTypesConfig{} = config
    end
  end

  describe "unsupported field types" do
    for {message, description, expected} <- [
          {Acme.Test.V1.TestUnsupportedRepeatedWithoutSplit, "a repeated field that never splits",
           "unsupported type repeated :string.*repeated fields require a split step"},
          {Acme.Test.V1.TestUnsupportedMessageField, "a message field", "unsupported type"},
          {Acme.Test.V1.TestUnsupportedMapField, "a map field", "unsupported type"},
          {Acme.Test.V1.TestUnsupportedEmptyEnvVar, "an extension with no env_var",
           "has an env_var extension but env_var is empty"}
        ] do
      test "rejects #{description}" do
        assert_raise CompileError, Regex.compile!(unquote(expected)), fn ->
          compile_env_module(unquote(message))
        end
      end
    end
  end

  describe "repeated fields with split_delimiter" do
    test "loads and splits string values into list" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "foo, bar, baz",
        "PORT_LIST" => "8080"
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.database_url == "postgres://localhost"
      assert config.env.tags == ["foo", "bar", "baz"]
    end

    test "converts and splits integer values into list" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "tag1, tag2",
        "PORT_LIST" => "8080, 9000, 3000"
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.port_list == [8080, 9000, 3000]
      assert is_list(config.env.port_list)
      assert Enum.all?(config.env.port_list, &is_integer/1)
    end

    test "handles single value without delimiter" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "single-tag",
        "PORT_LIST" => "3000"
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.tags == ["single-tag"]
    end

    test "trims unicode whitespace from split values" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "  foo  ,  bar  ,  baz  "
      })

      config = ConfigWithTrimUnicode.from_env!()

      assert config.env.tags == ["foo", "bar", "baz"]
    end

    test "trims custom characters from split values" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "*foo*, *bar*, *baz*"
      })

      config = ConfigWithTrimCustom.from_env!()

      assert config.env.tags == ["foo", "bar", "baz"]
    end

    test "handles trailing delimiter without crashing" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "foo, bar, ",
        "PORT_LIST" => "8080, 9000, "
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.tags == ["foo", "bar"]
      assert config.env.port_list == [8080, 9000]
    end

    test "handles leading delimiter without crashing" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => ", foo, bar",
        "PORT_LIST" => ", 8080, 9000"
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.tags == ["foo", "bar"]
      assert config.env.port_list == [8080, 9000]
    end

    test "handles consecutive delimiters without crashing" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "TAGS" => "foo, , bar",
        "PORT_LIST" => "8080, , 9000"
      })

      config = ConfigWithRepeated.from_env!()

      assert config.env.tags == ["foo", "bar"]
      assert config.env.port_list == [8080, 9000]
    end
  end

  describe "enum fields" do
    test "applies enum defaults when the scalar enum env var is absent" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "LOG_LEVELS" => ""
      })

      config = ConfigWithEnum.from_env!()

      assert config.env.database_url == "postgres://localhost"
      assert config.env.log_level == :LOG_LEVEL_INFO
      assert config.env.log_levels == []
    end

    test "converts enum env var values by exact name" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "LOG_LEVEL" => "LOG_LEVEL_DEBUG",
        "LOG_LEVELS" => "LOG_LEVEL_WARN, LOG_LEVEL_ERROR"
      })

      config = ConfigWithEnum.from_env!()

      assert config.env.log_level == :LOG_LEVEL_DEBUG
      assert config.env.log_levels == [:LOG_LEVEL_WARN, :LOG_LEVEL_ERROR]
    end

    test "trims repeated enum values before exact-name lookup" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "LOG_LEVELS" => "  LOG_LEVEL_WARN  ,  LOG_LEVEL_ERROR  "
      })

      config = ConfigWithEnum.from_env!()

      assert config.env.log_levels == [:LOG_LEVEL_WARN, :LOG_LEVEL_ERROR]
    end

    test "raises LoadError for enum env vars that do not match a value name exactly" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "LOG_LEVEL" => "debug",
        "LOG_LEVELS" => ""
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          ConfigWithEnum.from_env!()
        end

      assert error.errors == [
               %{
                 env_var: "LOG_LEVEL",
                 field: :log_level,
                 reason:
                   {:invalid,
                    ~s|not a valid enum name "debug" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN|}
               }
             ]

      assert Exception.message(error) == """
             failed to load 1 environment variable(s):
               - LOG_LEVEL invalid (not a valid enum name "debug" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN)
             """
    end

    test "does not cast numeric enum env vars by tag" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "LOG_LEVEL" => "1",
        "LOG_LEVELS" => ""
      })

      error =
        assert_raise Trogon.Proto.Env.LoadError, fn ->
          ConfigWithEnum.from_env!()
        end

      assert error.errors == [
               %{
                 env_var: "LOG_LEVEL",
                 field: :log_level,
                 reason:
                   {:invalid,
                    ~s|not a valid enum name "1" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN|}
               }
             ]

      assert Exception.message(error) == """
             failed to load 1 environment variable(s):
               - LOG_LEVEL invalid (not a valid enum name "1" for Acme.Test.V1.LogLevel. Expected one of: LOG_LEVEL_DEBUG, LOG_LEVEL_ERROR, LOG_LEVEL_INFO, LOG_LEVEL_UNSPECIFIED, LOG_LEVEL_WARN)
             """
    end

    test "raises CompileError for invalid enum defaults" do
      module = Module.concat(__MODULE__, :"InvalidEnumConfig#{System.unique_integer([:positive])}")

      quoted =
        quote do
          defmodule unquote(module) do
            use Trogon.Proto.Env, message: Acme.Test.V1.TestEnumInvalidDefault
          end
        end

      assert_raise CompileError, ~r/Field log_level has invalid default_value "debug"/, fn ->
        Code.compile_quoted(quoted)
      end
    end
  end

  describe "steps pipeline" do
    @raw_key String.duplicate("k", 32)

    defp steps_env(overrides) do
      Map.merge(
        %{
          "TOKEN_SIGNING_KEY" => Base.encode64(@raw_key),
          "SIGNATURE" => "DEADBEEF",
          "SESSION_ID" => "abcdefgh",
          "PORT_LIST" => "8080",
          "TAGS" => "foo"
        },
        overrides
      )
    end

    test "decodes a base64 value into bytes" do
      TestSupport.stub_system_env(steps_env(%{}))

      assert ConfigWithSteps.from_env!().env.token_signing_key == @raw_key
    end

    test "trims before decoding so a trailing newline is tolerated" do
      TestSupport.stub_system_env(steps_env(%{"TOKEN_SIGNING_KEY" => "  #{Base.encode64(@raw_key)}\n"}))

      assert ConfigWithSteps.from_env!().env.token_signing_key == @raw_key
    end

    test "falls back to utf8 when base64 does not satisfy accept" do
      TestSupport.stub_system_env(steps_env(%{"TOKEN_SIGNING_KEY" => @raw_key}))

      assert ConfigWithSteps.from_env!().env.token_signing_key == @raw_key
    end

    test "rejects a value no candidate decodes to an acceptable size" do
      TestSupport.stub_system_env(steps_env(%{"TOKEN_SIGNING_KEY" => Base.encode64("too short")}))

      assert {:error, error} = ConfigWithSteps.from_env()

      assert [%{env_var: "TOKEN_SIGNING_KEY", field: :token_signing_key, reason: {:invalid, reason}}] = error.errors

      assert reason ==
               "no acceptable decoding (attempted: base64(standard, required), utf8; " <>
                 "decoded byte sizes: 9, 12; expected exactly 32 bytes)"
    end

    test "never repeats the value in a decode failure" do
      secret = Base.encode64("too short")
      TestSupport.stub_system_env(steps_env(%{"TOKEN_SIGNING_KEY" => secret}))

      assert {:error, error} = ConfigWithSteps.from_env()

      refute Exception.message(error) =~ secret
    end

    test "decodes hex in either case" do
      TestSupport.stub_system_env(steps_env(%{"SIGNATURE" => "deadbeef"}))

      assert ConfigWithSteps.from_env!().env.signature == <<0xDE, 0xAD, 0xBE, 0xEF>>
    end

    test "rejects hex that is not hex" do
      TestSupport.stub_system_env(steps_env(%{"SIGNATURE" => "nothex!!"}))

      assert {:error, error} = ConfigWithSteps.from_env()

      assert [%{field: :signature, reason: {:invalid, reason}}] = error.errors
      assert reason == "no acceptable decoding (attempted: hex; nothing decoded)"
    end

    test "applies a require step to a trimmed value" do
      TestSupport.stub_system_env(steps_env(%{"SESSION_ID" => "  abcdefgh  "}))

      assert ConfigWithSteps.from_env!().env.session_id == "abcdefgh"
    end

    test "rejects a value outside the required byte size range" do
      TestSupport.stub_system_env(steps_env(%{"SESSION_ID" => "abc"}))

      assert {:error, error} = ConfigWithSteps.from_env()

      assert [%{field: :session_id, reason: {:invalid, reason}}] = error.errors
      assert reason == "byte size 3 does not satisfy between 8 and 16 bytes"
    end

    test "splits and trims repeated integers" do
      TestSupport.stub_system_env(steps_env(%{"PORT_LIST" => " 8080, 9000 ,3000 "}))

      assert ConfigWithSteps.from_env!().env.port_list == [8080, 9000, 3000]
    end

    test "applies consecutive trims to every element and drops the emptied ones" do
      TestSupport.stub_system_env(steps_env(%{"TAGS" => " *foo* , *bar*,**, "}))

      assert ConfigWithSteps.from_env!().env.tags == ["foo", "bar"]
    end

    test "runs default_value through the pipeline" do
      TestSupport.stub_system_env(%{})

      config = ConfigWithStepsDefault.from_env!()

      assert config.env.token_signing_key == <<0::256>>
      assert config.env.tags == ["a", "b"]
    end

    test "rejects a padded value when the candidate declares padding absent" do
      raw = String.duplicate(<<0xFF, 0xFE>>, 8)
      TestSupport.stub_system_env(%{"TOKEN_SIGNING_KEY" => Base.url_encode64(raw, padding: true)})

      assert {:error, error} = ConfigWithStepsUrlSafe.from_env()

      assert [%{field: :token_signing_key, reason: {:invalid, reason}}] = error.errors

      assert reason ==
               "no acceptable decoding (attempted: base64(url_safe, absent); nothing decoded; expected at least 16 bytes)"
    end

    test "decodes url safe base64 without padding" do
      raw = String.duplicate(<<0xFF, 0xFE>>, 8)
      TestSupport.stub_system_env(%{"TOKEN_SIGNING_KEY" => Base.url_encode64(raw, padding: false)})

      assert ConfigWithStepsUrlSafe.from_env!().env.token_signing_key == raw
    end
  end

  describe "steps pipeline schema validation" do
    for {message, description, expected} <- [
          {Acme.Test.V1.TestStepsWithDeprecated, "steps combined with deprecated fields",
           "declares steps together with the deprecated split_delimiter"},
          {Acme.Test.V1.TestStepsSplitOnScalar, "split on a non repeated field",
           "has a split step but is not repeated"},
          {Acme.Test.V1.TestStepsSplitNotFirst, "split that is not first", "has a split step that is not first"},
          {Acme.Test.V1.TestStepsEmptyDelimiter, "empty split delimiter", "has a split step with an empty delimiter"},
          {Acme.Test.V1.TestStepsDecodeOnInt, "decode on a numeric field",
           "has a decode step but type .* is not bytes or string"},
          {Acme.Test.V1.TestStepsTrimAfterDecode, "trim after decode", "has a trim step after its decode step"},
          {Acme.Test.V1.TestStepsCandidatesWithoutAccept, "several candidates without accept",
           "has a decode step with several candidates but no accept"},
          {Acme.Test.V1.TestStepsUtf8NotLast, "utf8 that is not last",
           "has a decode step where utf8 is not the last candidate"},
          {Acme.Test.V1.TestStepsUnspecifiedAlphabet, "unspecified base64 alphabet",
           "has a base64 candidate with an undeclared alphabet"},
          {Acme.Test.V1.TestStepsUnspecifiedPadding, "unspecified base64 padding",
           "has a base64 candidate with an undeclared padding"},
          {Acme.Test.V1.TestStepsEmptyRequire, "empty require", "has empty constraints"},
          {Acme.Test.V1.TestStepsByteSizeOnInt, "byte_size on a numeric field",
           "constrains byte_size but type .* is not bytes or string"},
          {Acme.Test.V1.TestStepsRangeWithoutBound, "byte_size range without a bound",
           "has a byte_size range without a bound"},
          {Acme.Test.V1.TestStepsInvertedRange, "byte_size range with min above max",
           "has a byte_size range with min 16 above max 8"},
          {Acme.Test.V1.TestStepsInvalidDefault, "a default the pipeline rejects",
           "has invalid default_value .* no acceptable decoding"},
          {Acme.Test.V1.TestStepsTwoSplits, "more than one split", "has more than one split step"},
          {Acme.Test.V1.TestStepsTwoDecodes, "more than one decode", "has more than one decode step"},
          {Acme.Test.V1.TestStepsDecodeWithoutCandidates, "decode without candidates",
           "has a decode step with no any_of candidates"},
          {Acme.Test.V1.TestStepsRepeatedCandidates, "repeated decode candidates",
           "has a decode step with repeated candidates"},
          {Acme.Test.V1.TestStepsCandidateWithoutAs, "a decode candidate without an encoding",
           "has a decode candidate without an as"},
          {Acme.Test.V1.TestStepsEmptyTrimChars, "an empty trim chars set", "has a trim step with an empty chars set"},
          {Acme.Test.V1.TestStepsTrimWithoutBy, "a trim without a by", "has a trim step without a by"},
          {Acme.Test.V1.TestStepsStepWithoutOp, "a step without an op", "has a step without an op"},
          {Acme.Test.V1.TestStepsByteSizeWithoutBound, "a byte_size without a bound", "has a byte_size without a bound"}
        ] do
      test "rejects #{description}" do
        assert_raise CompileError, Regex.compile!(unquote(expected)), fn ->
          compile_env_module(unquote(message))
        end
      end
    end
  end

  describe "annotations from a newer schema" do
    test "accepts the double that only uses options this package declares" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert [{_module, _bytecode} | _] = compile_env_module(FutureSchema.SupportedAnnotation)
      end)
    end

    for {message, description, expected} <- [
          {FutureSchema.FutureOption, "an undeclared field option",
           "written against a newer trogon.env.v1alpha1 than this package supports"},
          {FutureSchema.FutureEnvVarOption, "an undeclared env_var option",
           "written against a newer trogon.env.v1alpha1 than this package supports"},
          {FutureSchema.FutureVisibility, "an undeclared visibility", "has an undeclared visibility 7"}
        ] do
      test "rejects #{description}" do
        assert_raise CompileError, Regex.compile!(unquote(expected)), fn ->
          compile_env_module(unquote(message))
        end
      end
    end
  end

  defp compile_env_module(message) do
    module = Module.concat(__MODULE__, :"Invalid#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use Trogon.Proto.Env, message: unquote(message)
        end
      end
    )
  end
end
