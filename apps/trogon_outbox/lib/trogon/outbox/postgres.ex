defmodule Trogon.Outbox.Postgres do
  @moduledoc false

  @prefix ~r/\A[a-z_][a-z0-9_]{0,62}\z/

  @spec validate_prefix!(String.t()) :: String.t()
  def validate_prefix!(prefix) when is_binary(prefix) do
    if Regex.match?(@prefix, prefix),
      do: prefix,
      else: raise(ArgumentError, "the prefix must be a lowercase Postgres identifier, got: #{inspect(prefix)}")
  end

  @spec name(String.t(), String.t()) :: String.t()
  def name(prefix, object), do: ~s("#{validate_prefix!(prefix)}"."#{object}")

  @spec events(String.t()) :: String.t()
  def events(prefix), do: name(prefix, "outbox_events")

  @spec sources(String.t()) :: String.t()
  def sources(prefix), do: name(prefix, "outbox_sources")

  @spec cursors(String.t()) :: String.t()
  def cursors(prefix), do: name(prefix, "outbox_cursors")

  @spec relays(String.t()) :: String.t()
  def relays(prefix), do: name(prefix, "outbox_relays")

  @spec query!(module() | pid(), String.t(), list()) :: Postgrex.Result.t()
  def query!(repo, sql, params) when is_atom(repo), do: Ecto.Adapters.SQL.query!(repo, sql, params)
  def query!(conn, sql, params) when is_pid(conn), do: Postgrex.query!(conn, sql, params)

  @spec xid(String.t()) :: non_neg_integer()
  def xid(text), do: String.to_integer(text)
end
