defmodule Trogon.Outbox.TestSupport.SecondRepo do
  @moduledoc """
  A second Ecto repo pointed at the same database as `Trogon.Outbox.TestRepo`, with its own
  connection pool. Used to prove that an Oban instance configured with a repo other than the one
  running the business transaction does not share that transaction's connection.
  """

  use Ecto.Repo,
    otp_app: :trogon_outbox,
    adapter: Ecto.Adapters.Postgres
end
