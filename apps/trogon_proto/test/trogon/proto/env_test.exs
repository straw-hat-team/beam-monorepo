defmodule Trogon.Proto.EnvTest do
  use ExUnit.Case, async: true

  alias Trogon.Proto.EnvTestSupport.AllTypesConfig

  describe "struct generation" do
    test "generates struct with all fields" do
      config = %AllTypesConfig{
        database_url: "postgres://...",
        port: 5432,
        api_key: "secret-key",
        host: "localhost",
        timeout_ms: 30_000,
        max_memory_mb: 512.5,
        cpu_limit: 0.5,
        debug_mode: false
      }

      assert config.database_url == "postgres://..."
      assert config.port == 5432
      assert config.api_key == "secret-key"
      assert config.host == "localhost"
      assert config.timeout_ms == 30_000
      assert config.max_memory_mb == 512.5
      assert config.cpu_limit == 0.5
      assert config.debug_mode == false
    end

    test "struct fields are optional (default to nil)" do
      config = %AllTypesConfig{}

      assert config.database_url == nil
      assert config.port == nil
      assert config.api_key == nil
      assert config.host == nil
    end
  end

  describe "load!/0 function" do
    test "loads required fields from environment" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "my-secret-key")

      config = AllTypesConfig.load!()

      assert config.database_url == "postgres://localhost"
      assert config.api_key == "my-secret-key"
      assert config.port == 5432
      assert config.host == "localhost"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end

    test "raises ArgumentError when required field is missing" do
      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")

      assert_raise ArgumentError, ~r/Required environment variable/, fn ->
        AllTypesConfig.load!()
      end
    end

    test "raises ArgumentError when another required field is missing" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.delete_env("API_KEY")

      assert_raise ArgumentError, ~r/Required environment variable API_KEY/, fn ->
        AllTypesConfig.load!()
      end

      System.delete_env("DATABASE_URL")
    end

    test "applies default values for optional fields" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")

      config = AllTypesConfig.load!()

      assert config.port == 5432
      assert config.host == "localhost"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end

    test "overrides default values with environment variables" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("PORT", "8080")
      System.put_env("HOST", "example.com")

      config = AllTypesConfig.load!()

      assert config.port == 8080
      assert config.host == "example.com"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("PORT")
      System.delete_env("HOST")
    end
  end

  describe "type conversion" do
    test "converts int32 fields from strings" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("PORT", "8080")

      config = AllTypesConfig.load!()

      assert config.port == 8080
      assert is_integer(config.port)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("PORT")
    end

    test "converts int64 fields from strings" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("TIMEOUT_MS", "5000")

      config = AllTypesConfig.load!()

      assert config.timeout_ms == 5000
      assert is_integer(config.timeout_ms)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("TIMEOUT_MS")
    end

    test "converts float fields from strings" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("MAX_MEMORY_MB", "256.5")

      config = AllTypesConfig.load!()

      assert config.max_memory_mb == 256.5
      assert is_float(config.max_memory_mb)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("MAX_MEMORY_MB")
    end

    test "converts double fields from strings" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("CPU_LIMIT", "0.75")

      config = AllTypesConfig.load!()

      assert config.cpu_limit == 0.75
      assert is_float(config.cpu_limit)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("CPU_LIMIT")
    end

    test "converts bool fields from strings" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("DEBUG_MODE", "true")

      config = AllTypesConfig.load!()

      assert config.debug_mode == true
      assert is_boolean(config.debug_mode)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("DEBUG_MODE")
    end

    test "bool field handles various truthy values" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")

      # Test "1"
      System.put_env("DEBUG_MODE", "1")
      config1 = AllTypesConfig.load!()
      assert config1.debug_mode == true

      # Test "yes"
      System.put_env("DEBUG_MODE", "yes")
      config2 = AllTypesConfig.load!()
      assert config2.debug_mode == true

      # Test "on"
      System.put_env("DEBUG_MODE", "on")
      config3 = AllTypesConfig.load!()
      assert config3.debug_mode == true

      # Test falsy value
      System.put_env("DEBUG_MODE", "false")
      config4 = AllTypesConfig.load!()
      assert config4.debug_mode == false

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("DEBUG_MODE")
    end

    test "applies defaults with correct types" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")

      config = AllTypesConfig.load!()

      # Verify defaults are applied as correct types
      assert config.port == 5432
      assert is_integer(config.port)

      assert config.timeout_ms == 30_000
      assert is_integer(config.timeout_ms)

      assert config.max_memory_mb == 512.5
      assert is_float(config.max_memory_mb)

      assert config.cpu_limit == 0.5
      assert is_float(config.cpu_limit)

      assert config.debug_mode == false
      assert is_boolean(config.debug_mode)

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end
  end

  describe "inspect protocol" do
    test "masks secret fields in inspect output" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "very-secret")

      config = AllTypesConfig.load!()
      inspected = inspect(config)

      assert inspected =~ "***SECRET***"
      refute inspected =~ "postgres://localhost"
      refute inspected =~ "very-secret"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end

    test "shows plaintext fields in inspect output" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")
      System.put_env("PORT", "9000")
      System.put_env("HOST", "api.example.com")

      config = AllTypesConfig.load!()
      inspected = inspect(config)

      # Port is converted to integer
      assert inspected =~ "9000"
      assert inspected =~ "api.example.com"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
      System.delete_env("PORT")
      System.delete_env("HOST")
    end

    test "safe for logging without exposing secrets" do
      System.put_env("DATABASE_URL", "postgres://sensitive.db")
      System.put_env("API_KEY", "sk-very-sensitive-key")

      config = AllTypesConfig.load!()
      log_output = "Config: #{inspect(config)}"

      refute log_output =~ "postgres://sensitive.db"
      refute log_output =~ "sk-very-sensitive-key"
      assert log_output =~ "***SECRET***"

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end
  end

  describe "type specifications" do
    test "struct is of correct type" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("API_KEY", "secret")

      config = AllTypesConfig.load!()

      # Just verify it's a AllTypesConfig struct
      assert %AllTypesConfig{} = config

      System.delete_env("DATABASE_URL")
      System.delete_env("API_KEY")
    end
  end

  describe "unsupported field types" do
    test "repeated fields are skipped (not added to struct)" do
      # ConfigWithUnsupported has database_url (supported) and tags (unsupported repeated)
      # Only database_url should be included in the config
      System.put_env("DATABASE_URL", "postgres://localhost")

      # Load should work because only database_url is required
      config = Trogon.Proto.EnvTestSupport.ConfigWithUnsupported.load!()

      # database_url should exist
      assert config.database_url == "postgres://localhost"

      # tags field should not exist in the struct
      refute Map.has_key?(config, :tags)

      System.delete_env("DATABASE_URL")
    end
  end

  describe "repeated fields with split_delimiter" do
    test "loads and splits string values into list" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("TAGS", "foo, bar, baz")
      System.put_env("PORT_LIST", "8080")

      config = Trogon.Proto.EnvTestSupport.ConfigWithRepeated.load!()

      assert config.database_url == "postgres://localhost"
      assert config.tags == ["foo", "bar", "baz"]

      System.delete_env("DATABASE_URL")
      System.delete_env("TAGS")
      System.delete_env("PORT_LIST")
    end

    test "converts and splits integer values into list" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("TAGS", "tag1, tag2")
      System.put_env("PORT_LIST", "8080, 9000, 3000")

      config = Trogon.Proto.EnvTestSupport.ConfigWithRepeated.load!()

      assert config.port_list == [8080, 9000, 3000]
      assert is_list(config.port_list)
      assert Enum.all?(config.port_list, &is_integer/1)

      System.delete_env("DATABASE_URL")
      System.delete_env("TAGS")
      System.delete_env("PORT_LIST")
    end

    test "handles single value without delimiter" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("TAGS", "single-tag")
      System.put_env("PORT_LIST", "3000")

      config = Trogon.Proto.EnvTestSupport.ConfigWithRepeated.load!()

      assert config.tags == ["single-tag"]

      System.delete_env("DATABASE_URL")
      System.delete_env("TAGS")
      System.delete_env("PORT_LIST")
    end

    test "trims unicode whitespace from split values" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("TAGS", "  foo  ,  bar  ,  baz  ")

      config = Trogon.Proto.EnvTestSupport.ConfigWithTrimUnicode.load!()

      assert config.tags == ["foo", "bar", "baz"]

      System.delete_env("DATABASE_URL")
      System.delete_env("TAGS")
    end

    test "trims custom characters from split values" do
      System.put_env("DATABASE_URL", "postgres://localhost")
      System.put_env("TAGS", "*foo*, *bar*, *baz*")

      config = Trogon.Proto.EnvTestSupport.ConfigWithTrimCustom.load!()

      assert config.tags == ["foo", "bar", "baz"]

      System.delete_env("DATABASE_URL")
      System.delete_env("TAGS")
    end
  end
end
