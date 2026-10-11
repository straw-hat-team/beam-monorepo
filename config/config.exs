# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

if config_env() == :test do
  config :trogon_proto, Trogon.Proto.Env, system: Trogon.Proto.TestSupport.SystemAdapter.Mock

  config :trogon_configurable, Trogon.Configurable, application: Trogon.Test.MockApplication

  config :trogon_test, :seeded_value, "real value"
  config :trogon_test, :seeded_list, a: 1, b: 2
end
