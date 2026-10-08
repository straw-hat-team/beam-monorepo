defmodule Trogon.Outbox.PostgresVersion do
  @moduledoc """
  The connected server's `server_version_num`, checked against the version the outbox requires.

  The outbox requires Postgres 17 or later. A writer role needs `transaction_timeout`, added in
  Postgres 17, to bound how long an open transaction can hold back the snapshot watermark that
  every relay reads behind; see `Trogon.Outbox.Relay` and the "Commit order within a source"
  section of the design doc.
  """

  alias Trogon.Outbox.Postgres

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: non_neg_integer()}

  @minimum 170_000

  @spec new!(non_neg_integer()) :: t()
  def new!(value) when is_integer(value) and value >= 0, do: %__MODULE__{value: value}

  @doc "The lowest `server_version_num` the outbox supports."
  @spec minimum() :: pos_integer()
  def minimum, do: @minimum

  @spec supported?(t()) :: boolean()
  def supported?(%__MODULE__{value: value}), do: value >= @minimum

  @doc "Queries `server_version_num` from `repo` or a connection `pid`."
  @spec fetch!(module() | pid()) :: t()
  def fetch!(conn) do
    %Postgrex.Result{rows: [[value]]} =
      Postgres.query!(conn, "SELECT current_setting('server_version_num')::int", [])

    new!(value)
  end

  @doc "Raises `ArgumentError` when `version` is below `minimum/0`."
  @spec ensure_supported!(t()) :: :ok
  def ensure_supported!(%__MODULE__{} = version) do
    unless supported?(version) do
      raise ArgumentError,
            "Trogon.Outbox requires Postgres #{div(@minimum, 10_000)} or later, because a writer role " <>
              "needs transaction_timeout to bound the snapshot watermark; the connected server reports " <>
              "server_version_num #{version.value}"
    end

    :ok
  end

  defimpl String.Chars do
    def to_string(%{value: value}), do: Integer.to_string(value)
  end
end
