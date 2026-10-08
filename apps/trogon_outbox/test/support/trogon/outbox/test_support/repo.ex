defmodule Trogon.Outbox.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :trogon_outbox,
    adapter: Ecto.Adapters.Postgres
end
