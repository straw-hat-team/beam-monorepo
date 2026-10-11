defmodule Trogon.ConfigurableTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  defmodule Static do
    use Trogon.Configurable, config: [site: "https://static.example", retries: 1]
  end

  defmodule Environment do
    use Trogon.Configurable, otp_app: :my_app, config: [site: "https://static.example", retries: 1]
  end

  defmodule Attributes do
    @app :my_app
    @defaults [site: "https://static.example", retries: 1]

    use Trogon.Configurable, otp_app: @app, config: @defaults
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

  test "accepts options built from module attributes" do
    TestApplication.expect_get_env(returns: [site: "https://environment.example"])

    assert Attributes.get_config() == [retries: 1, site: "https://environment.example"]
    TestApplication.assert_received_get_env(:my_app, Attributes, [])
    Trogon.Test.assert_empty_mailbox()
  end

  test "returns an empty configuration when nothing is configured" do
    assert Unconfigured.get_config() == []
  end

  test "an unknown option fails the compilation" do
    assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:confg\]/, fn ->
      defmodule Misspelled do
        use Trogon.Configurable, confg: [site: "https://static.example"]
      end
    end
  end

  test "an option of the wrong type fails the compilation" do
    assert_raise NimbleOptions.ValidationError, ~r/invalid value for :otp_app option/, fn ->
      defmodule WrongType do
        use Trogon.Configurable, otp_app: "my_app"
      end
    end
  end

  test "a module's own application setting overrides the global one" do
    Application.put_env(:trogon_configurable, Trogon.ConfigurableTest.PerModule, application: Application)
    Application.put_env(:my_app, Trogon.ConfigurableTest.PerModule, site: "https://environment.example")

    on_exit(fn ->
      Application.delete_env(:trogon_configurable, Trogon.ConfigurableTest.PerModule)
      Application.delete_env(:my_app, Trogon.ConfigurableTest.PerModule)
    end)

    defmodule PerModule do
      use Trogon.Configurable, otp_app: :my_app
    end

    assert PerModule.get_config() == [site: "https://environment.example"]
    Trogon.Test.assert_empty_mailbox()
  end
end
