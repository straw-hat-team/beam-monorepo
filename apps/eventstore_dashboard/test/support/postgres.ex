defmodule EventStoreDashboard.Test.Postgres do
  @moduledoc false

  # Tests tagged `:postgres` run only when this variable points at a Postgres
  # the suite may create and initialize an event store database in.
  @url_env "EVENTSTORE_DASHBOARD_DATABASE_URL"

  alias EventStore.Config.Parser
  alias EventStore.Tasks.{Create, Drop, Init}
  alias EventStoreDashboard.Repo.Context

  def configured?, do: System.get_env(@url_env) not in [nil, ""]

  def config(overrides \\ []) do
    [url: System.fetch_env!(@url_env), schema: "public", column_data_type: "bytea"]
    |> Parser.parse()
    |> Keyword.merge(overrides)
  end

  def setup_database!(config) do
    Drop.exec(config, quiet: true)
    Create.exec(config, quiet: true)
    Init.exec(config, quiet: true)
  end

  def connect!(config) do
    {:ok, conn} =
      config
      |> Keyword.take([:hostname, :port, :username, :password, :database])
      |> Keyword.put(:pool_size, 1)
      |> Postgrex.start_link()

    conn
  end

  def context(conn), do: %Context{event_store: {__MODULE__, []}, conn: conn, schema: "public"}

  def query!(conn, sql, params \\ []), do: Postgrex.query!(conn, sql, params)
end
