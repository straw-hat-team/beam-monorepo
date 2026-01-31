defmodule Trogon.Proto.EnvTest do
  use ExUnit.Case, async: true

  alias Trogon.Proto.Env
  alias Trogon.Proto.TestSupport
  alias Trogon.Proto.TestSupport.AllTypesConfig
  alias Trogon.Proto.TestSupport.ConfigWithRepeated
  alias Trogon.Proto.TestSupport.ConfigWithTrimCustom
  alias Trogon.Proto.TestSupport.ConfigWithTrimUnicode
  alias Trogon.Proto.TestSupport.ConfigWithUnsupported

  setup {Mox, :set_mox_from_context}

  # Unit tests for convert_field/2 - tests type conversion with proto atom types
  describe "convert_field/2" do
    test "converts :TYPE_STRING to string (passthrough)" do
      config = %{field_type: :TYPE_STRING, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("hello world", config) == "hello world"
    end

    test "converts :TYPE_INT32 to integer" do
      config = %{field_type: :TYPE_INT32, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("42", config) == 42
      assert Env.convert_field("-100", config) == -100
    end

    test "converts :TYPE_INT64 to integer" do
      config = %{field_type: :TYPE_INT64, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("9223372036854775807", config) == 9_223_372_036_854_775_807
    end

    test "converts :TYPE_FLOAT to float" do
      config = %{field_type: :TYPE_FLOAT, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("3.14", config) == 3.14
      assert Env.convert_field("42", config) == 42.0
    end

    test "converts :TYPE_DOUBLE to float" do
      config = %{field_type: :TYPE_DOUBLE, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("2.718281828", config) == 2.718281828
    end

    test "converts :TYPE_BOOL truthy values to true" do
      config = %{field_type: :TYPE_BOOL, is_repeated: false, split_delimiter: "", trim: nil}

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
      config = %{field_type: :TYPE_BOOL, is_repeated: false, split_delimiter: "", trim: nil}

      assert Env.convert_field("false", config) == false
      assert Env.convert_field("0", config) == false
      assert Env.convert_field("no", config) == false
      assert Env.convert_field("off", config) == false
      assert Env.convert_field("anything_else", config) == false
    end

    test "handles repeated :TYPE_STRING with split_delimiter" do
      config = %{field_type: :TYPE_STRING, is_repeated: true, split_delimiter: ",", trim: nil}

      assert Env.convert_field("a,b,c", config) == ["a", "b", "c"]
    end

    test "handles repeated :TYPE_INT32 with split_delimiter" do
      config = %{field_type: :TYPE_INT32, is_repeated: true, split_delimiter: ",", trim: nil}

      assert Env.convert_field("1,2,3", config) == [1, 2, 3]
    end

    test "handles repeated fields with unicode_whitespace trim" do
      config = %{
        field_type: :TYPE_STRING,
        is_repeated: true,
        split_delimiter: ",",
        trim: %{by: {:unicode_whitespace, %{}}}
      }

      assert Env.convert_field("  a  ,  b  ,  c  ", config) == ["a", "b", "c"]
    end

    test "handles repeated fields with custom chars trim" do
      config = %{
        field_type: :TYPE_STRING,
        is_repeated: true,
        split_delimiter: ",",
        trim: %{by: {:chars, "*"}}
      }

      assert Env.convert_field("*a*,*b*,*c*", config) == ["a", "b", "c"]
    end

    test "filters empty strings from repeated fields" do
      config = %{field_type: :TYPE_STRING, is_repeated: true, split_delimiter: ",", trim: nil}

      assert Env.convert_field("a,,b,", config) == ["a", "b"]
    end

    test "raises ArgumentError for invalid float" do
      config = %{field_type: :TYPE_FLOAT, is_repeated: false, split_delimiter: "", trim: nil}

      assert_raise ArgumentError, ~r/not a valid float/, fn ->
        Env.convert_field("not_a_number", config)
      end
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

    test "raises System.EnvError when DATABASE_URL is missing" do
      TestSupport.stub_system_env(%{
        "API_KEY" => "secret"
      })

      error =
        assert_raise System.EnvError, fn ->
          AllTypesConfig.from_env!()
        end

      assert error.env == "DATABASE_URL"
    end

    test "raises System.EnvError when API_KEY is missing" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost"
      })

      error =
        assert_raise System.EnvError, fn ->
          AllTypesConfig.from_env!()
        end

      assert error.env == "API_KEY"
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

    test "raises ArgumentError for invalid float value" do
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost",
        "API_KEY" => "secret",
        "MAX_MEMORY_MB" => "not_a_float"
      })

      assert_raise ArgumentError, ~r/not a valid float/, fn ->
        AllTypesConfig.from_env!()
      end
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
    test "repeated fields are skipped (not added to struct)" do
      # ConfigWithUnsupported has database_url (supported) and tags (unsupported repeated)
      # Only database_url should be included in the config
      TestSupport.stub_system_env(%{
        "DATABASE_URL" => "postgres://localhost"
      })

      # Load should work because only database_url is required
      config = ConfigWithUnsupported.from_env!()

      # database_url should exist
      assert config.env.database_url == "postgres://localhost"

      # tags was not loaded from env (unsupported repeated without split_delimiter), so default []
      assert config.env.tags == []
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
end
