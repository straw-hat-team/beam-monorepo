defmodule Trogon.Outbox.TestSupport.OldPostgresSupport do
  @moduledoc """
  Points a dedicated repo at a Postgres server older than 17, to prove the outbox's minimum
  version check fails loudly instead of running against an unsupported server.

  Every test using this support module is skipped unless `TROGON_OUTBOX_PG16_URL` is set, the
  same way the RabbitMQ and PgBouncer tests are skipped without their own URLs.
  """

  defmodule Repo do
    @moduledoc false
    use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
  end

  @spec url() :: String.t() | nil
  def url, do: System.get_env("TROGON_OUTBOX_PG16_URL")

  @spec skip_reason() :: String.t()
  def skip_reason, do: "set TROGON_OUTBOX_PG16_URL to a Postgres older than 17 to test"

  @doc "Starts and returns the repo connected to the old server."
  @spec start_repo!() :: module()
  def start_repo! do
    Application.put_env(:trogon_outbox, Repo, url: url(), pool_size: 2)
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:trogon_outbox, Repo) end)
    ExUnit.Callbacks.start_supervised!(Repo)
    Repo
  end
end
