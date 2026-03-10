defmodule Trogon.ExunitReporter.ConfigTest do
  use ExUnit.Case, async: true

  alias Trogon.ExunitReporter.Config

  describe "from_exunit_opts/1" do
    test "returns defaults when no options given" do
      assert {:ok, config} = Config.from_exunit_opts([])
      assert config.file_path == "test-report.txt"
      assert config.include_logs == true
    end

    test "accepts valid custom options" do
      opts = [
        trogon_exunit_reporter: [
          file_path: "custom-report.txt",
          include_logs: false
        ]
      ]

      assert {:ok, config} = Config.from_exunit_opts(opts)
      assert config.file_path == "custom-report.txt"
      assert config.include_logs == false
    end

    test "returns error for invalid file_path type" do
      opts = [trogon_exunit_reporter: [file_path: 123]]
      assert {:error, %NimbleOptions.ValidationError{}} = Config.from_exunit_opts(opts)
    end
  end

  describe "from_exunit_opts!/1" do
    test "returns config struct with defaults" do
      config = Config.from_exunit_opts!([])
      assert %Config{} = config
      assert config.file_path == "test-report.txt"
    end

    test "raises on invalid options" do
      opts = [trogon_exunit_reporter: [file_path: 123]]

      assert_raise NimbleOptions.ValidationError, fn ->
        Config.from_exunit_opts!(opts)
      end
    end
  end
end
