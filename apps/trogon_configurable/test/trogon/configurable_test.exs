defmodule Trogon.ConfigurableTest do
  use ExUnit.Case, async: false

  defmodule Static do
    use Trogon.Configurable, config: [site: "https://static.example", retries: 1]
  end

  defmodule Environment do
    use Trogon.Configurable, otp_app: :trogon_configurable, config: [site: "https://static.example", retries: 1]
  end

  defmodule Unconfigured do
    use Trogon.Configurable
  end

  setup do
    Application.put_env(:trogon_configurable, Environment, site: "https://environment.example")
    Application.put_env(:trogon_configurable, Static, site: "https://ignored.example")

    on_exit(fn ->
      Application.delete_env(:trogon_configurable, Environment)
      Application.delete_env(:trogon_configurable, Static)
    end)
  end

  test "returns the static configuration" do
    assert Static.get_config() == [site: "https://static.example", retries: 1]
  end

  test "ignores the environment when no otp_app is given" do
    assert Static.get_config()[:site] == "https://static.example"
  end

  test "the environment overrides the static configuration" do
    assert Environment.get_config() == [retries: 1, site: "https://environment.example"]
  end

  test "the parameters override the environment" do
    assert Environment.get_config(site: "https://runtime.example", timeout: 5) ==
             [retries: 1, site: "https://runtime.example", timeout: 5]
  end

  test "returns an empty configuration when nothing is configured" do
    assert Unconfigured.get_config() == []
  end
end
