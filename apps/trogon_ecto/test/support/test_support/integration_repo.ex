defmodule Trogon.Ecto.TestSupport.IntegrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :trogon_ecto, adapter: Ecto.Adapters.Postgres

  @doc false
  @spec test_config() :: Keyword.t()
  def test_config do
    [
      username: System.get_env("POSTGRES_USER", "postgres"),
      password: System.get_env("POSTGRES_PASSWORD", "postgres"),
      hostname: System.get_env("POSTGRES_HOST", "localhost"),
      port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
      database: System.get_env("POSTGRES_DATABASE", "trogon_ecto_integration_test"),
      pool_size: 2,
      log: false
    ]
  end
end
