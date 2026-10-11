defmodule Trogon.ConfigurableTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  defmodule Static do
    use Trogon.Configurable, config: [site: "https://static.example", retries: 1]
  end

  defmodule Environment do
    use Trogon.Configurable, otp_app: :my_app, config: [site: "https://static.example", retries: 1]
  end

  defmodule Unconfigured do
    use Trogon.Configurable
  end

  test "returns the static configuration without reading the environment" do
    assert Static.get_config() == [site: "https://static.example", retries: 1]
    Trogon.Test.assert_empty_mailbox()
  end

  test "the environment overrides the static configuration" do
    TestApplication.expect_get_env(returns: [site: "https://environment.example"])

    assert Environment.get_config() == [retries: 1, site: "https://environment.example"]
    TestApplication.assert_received_get_env(:my_app, Environment, [])
    Trogon.Test.assert_empty_mailbox()
  end

  test "the parameters override the environment" do
    TestApplication.expect_get_env(returns: [site: "https://environment.example"])

    assert Environment.get_config(site: "https://runtime.example", timeout: 5) ==
             [retries: 1, site: "https://runtime.example", timeout: 5]

    TestApplication.assert_received_get_env(:my_app, Environment, [])
    Trogon.Test.assert_empty_mailbox()
  end

  test "keeps the static configuration when the environment has none" do
    assert Environment.get_config() == [site: "https://static.example", retries: 1]
  end

  test "returns an empty configuration when nothing is configured" do
    assert Unconfigured.get_config() == []
  end
end
