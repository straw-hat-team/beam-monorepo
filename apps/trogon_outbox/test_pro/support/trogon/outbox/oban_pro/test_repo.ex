defmodule Trogon.Outbox.ObanPro.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :trogon_outbox,
    adapter: Ecto.Adapters.Postgres
end
