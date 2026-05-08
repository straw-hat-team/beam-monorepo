defmodule EventStoreDashboard.Repo do
  @moduledoc false

  require Logger

  alias EventStore.UUID
  alias EventStoreDashboard.{Event, Snapshot, Stream, Subscription}
  alias EventStoreDashboard.Repo.Context

  def fetch_conn(node, {_module, opts} = event_store) do
    name = Keyword.fetch!(opts, :name)

    case :rpc.call(node, EventStore.Config, :lookup, [name]) do
      config when is_list(config) ->
        case Keyword.get(config, :conn) do
          nil ->
            :error

          conn ->
            {:ok,
             %Context{
               event_store: event_store,
               conn: conn,
               schema: Keyword.get(config, :schema, "public"),
               serializer: Keyword.get(config, :serializer)
             }}
        end

      _ ->
        :error
    end
  end

  def query(node, conn, sql, params) do
    case :rpc.call(node, Postgrex, :query, [conn, sql, params]) do
      {:ok, %Postgrex.Result{rows: rows}} ->
        {:ok, rows}

      other ->
        Logger.debug(fn ->
          "EventStoreDashboard.Repo.query failed: #{inspect(other)}\nSQL: #{sql}\nParams: #{inspect(params)}"
        end)

        :error
    end
  end

  def fetch_stream(node, %Context{} = ctx, stream_uuid) do
    sql =
      "SELECT stream_id, stream_version, created_at, deleted_at " <>
        "FROM #{ctx.schema}.streams WHERE stream_uuid = $1 LIMIT 1;"

    case query(node, ctx.conn, sql, [stream_uuid]) do
      {:ok, [[stream_id, version, created_at, deleted_at]]} ->
        {:ok,
         %Stream{
           stream_id: stream_id,
           stream_uuid: stream_uuid,
           stream_version: version || 0,
           created_at: created_at,
           deleted_at: deleted_at,
           status: if(is_nil(deleted_at), do: :created, else: :deleted)
         }}

      {:ok, []} ->
        {:error, :stream_not_found}

      _ ->
        :error
    end
  end

  def query_events_in_stream(node, %Context{} = ctx, stream_id, sort_dir, type_filter, limit, offset) do
    direction = sort_dir_sql(sort_dir)
    {type_clause, params} = event_type_clause(type_filter, [stream_id, limit, offset], 4)

    sql = """
    SELECT
      se.stream_version,
      e.event_id,
      s.stream_uuid,
      se.original_stream_version,
      e.event_type,
      e.correlation_id,
      e.causation_id,
      e.data,
      e.metadata,
      e.created_at
    FROM #{ctx.schema}.stream_events se
    INNER JOIN #{ctx.schema}.events e ON e.event_id = se.event_id
    INNER JOIN #{ctx.schema}.streams s ON s.stream_id = se.original_stream_id
    WHERE se.stream_id = $1#{type_clause}
    ORDER BY se.stream_version #{direction}
    LIMIT $2 OFFSET $3;
    """

    query(node, ctx.conn, sql, params)
  end

  def count_events_in_stream(node, %Context{} = ctx, stream_id, type_filter) do
    {type_clause, params} = event_type_clause(type_filter, [stream_id], 2)

    sql = """
    SELECT COUNT(*)
    FROM #{ctx.schema}.stream_events se
    INNER JOIN #{ctx.schema}.events e ON e.event_id = se.event_id
    WHERE se.stream_id = $1#{type_clause};
    """

    case query(node, ctx.conn, sql, params) do
      {:ok, [[count]]} -> {:ok, count}
      _ -> :error
    end
  end

  def query_events_after_version(node, %Context{} = ctx, stream_id, after_version, limit) do
    sql = """
    SELECT
      se.stream_version,
      e.event_id,
      s.stream_uuid,
      se.original_stream_version,
      e.event_type,
      e.correlation_id,
      e.causation_id,
      e.data,
      e.metadata,
      e.created_at
    FROM #{ctx.schema}.stream_events se
    INNER JOIN #{ctx.schema}.events e ON e.event_id = se.event_id
    INNER JOIN #{ctx.schema}.streams s ON s.stream_id = se.original_stream_id
    WHERE se.stream_id = $1 AND se.stream_version > $2
    ORDER BY se.stream_version ASC
    LIMIT $3;
    """

    query(node, ctx.conn, sql, [stream_id, after_version, limit])
  end

  def query_event_at_version(node, %Context{} = ctx, stream_id, stream_version) do
    sql = """
    SELECT
      se.stream_version,
      e.event_id,
      s.stream_uuid,
      se.original_stream_version,
      e.event_type,
      e.correlation_id,
      e.causation_id,
      e.data,
      e.metadata,
      e.created_at
    FROM #{ctx.schema}.stream_events se
    INNER JOIN #{ctx.schema}.events e ON e.event_id = se.event_id
    INNER JOIN #{ctx.schema}.streams s ON s.stream_id = se.original_stream_id
    WHERE se.stream_id = $1 AND se.stream_version = $2
    LIMIT 1;
    """

    case query(node, ctx.conn, sql, [stream_id, stream_version]) do
      {:ok, [row]} -> {:ok, row}
      {:ok, []} -> {:error, :event_not_found}
      _ -> :error
    end
  end

  def row_to_event(
        [
          stream_version,
          event_id,
          stream_uuid,
          original_stream_version,
          event_type,
          correlation_id,
          causation_id,
          data,
          metadata,
          created_at
        ],
        %Context{} = ctx
      ) do
    %Event{
      event_number: stream_version,
      stream_version: original_stream_version,
      event_id: UUID.binary_to_string!(event_id),
      stream_uuid: stream_uuid,
      event_type: event_type,
      correlation_id: correlation_id && UUID.binary_to_string!(correlation_id),
      causation_id: causation_id && UUID.binary_to_string!(causation_id),
      data: deserialize(ctx.serializer, data, type: event_type),
      metadata: deserialize(ctx.serializer, metadata, []),
      created_at: created_at
    }
  end

  def count_events_by_id(node, %Context{} = ctx, column, value, type_filter \\ nil)
      when column in [:correlation_id, :causation_id] do
    with {:ok, uuid} <- string_to_uuid(value) do
      {type_clause, params} = event_type_clause(type_filter, [uuid], 2)

      sql =
        "SELECT COUNT(*) FROM #{ctx.schema}.events e WHERE e.#{column} = $1#{type_clause};"

      case query(node, ctx.conn, sql, params) do
        {:ok, [[count]]} -> {:ok, count}
        _ -> :error
      end
    end
  end

  def string_to_uuid(value) when is_binary(value) do
    {:ok, UUID.string_to_binary!(value)}
  rescue
    _ -> :error
  end

  def string_to_uuid(_), do: :error

  def count_snapshots(node, %Context{} = ctx, search_term) do
    {where, params} = snapshot_search_clause(search_term, [], 1)

    sql = "SELECT COUNT(*) FROM #{ctx.schema}.snapshots#{where};"

    case query(node, ctx.conn, sql, params) do
      {:ok, [[count]]} -> {:ok, count}
      _ -> :error
    end
  end

  @snapshot_sort_columns ~w(source_uuid source_type source_version created_at)a

  def query_snapshots(node, %Context{} = ctx, sort_by, sort_dir, search_term, limit, offset)
      when sort_by in @snapshot_sort_columns and sort_dir in [:asc, :desc] do
    direction = sort_dir_sql(sort_dir)
    {where, params} = snapshot_search_clause(search_term, [limit, offset], 3)

    sql = """
    SELECT source_uuid, source_version, source_type, created_at
    FROM #{ctx.schema}.snapshots#{where}
    ORDER BY #{sort_by} #{direction}
    LIMIT $1 OFFSET $2;
    """

    query(node, ctx.conn, sql, params)
  end

  def row_to_snapshot_summary([source_uuid, source_version, source_type, created_at]) do
    %{
      source_uuid: source_uuid,
      source_version: source_version,
      source_type: source_type,
      created_at: created_at
    }
  end

  def fetch_snapshot_summary(node, %Context{} = ctx, source_uuid) do
    sql = """
    SELECT source_uuid, source_version, source_type, created_at
    FROM #{ctx.schema}.snapshots
    WHERE source_uuid = $1
    LIMIT 1;
    """

    case query(node, ctx.conn, sql, [source_uuid]) do
      {:ok, [row]} -> {:ok, row_to_snapshot_summary(row)}
      {:ok, []} -> {:error, :snapshot_not_found}
      _ -> :error
    end
  end

  def fetch_snapshot(node, %Context{} = ctx, source_uuid) do
    sql = """
    SELECT source_uuid, source_version, source_type, data, metadata, created_at
    FROM #{ctx.schema}.snapshots
    WHERE source_uuid = $1
    LIMIT 1;
    """

    case query(node, ctx.conn, sql, [source_uuid]) do
      {:ok, [[uuid, version, type, data, metadata, created_at]]} ->
        {:ok,
         %Snapshot{
           source_uuid: uuid,
           source_version: version,
           source_type: type,
           data: deserialize(ctx.serializer, data, type: type),
           metadata: deserialize(ctx.serializer, metadata, []),
           created_at: created_at
         }}

      {:ok, []} ->
        {:error, :snapshot_not_found}

      _ ->
        :error
    end
  end

  def fetch_subscription_by_id(node, %Context{} = ctx, subscription_id) do
    sql = """
    SELECT
      s.subscription_id,
      s.stream_uuid,
      s.subscription_name,
      s.last_seen,
      s.created_at,
      st.stream_version
    FROM #{ctx.schema}.subscriptions s
    LEFT JOIN #{ctx.schema}.streams st ON st.stream_uuid = s.stream_uuid
    WHERE s.subscription_id = $1
    LIMIT 1;
    """

    case query(node, ctx.conn, sql, [subscription_id]) do
      {:ok, [[id, stream_uuid, name, last_seen, created_at, stream_version]]} ->
        version = stream_version || 0
        seen = last_seen || 0

        {:ok,
         %Subscription{
           subscription_id: id,
           stream_uuid: stream_uuid,
           subscription_name: name,
           last_seen: last_seen,
           stream_version: version,
           lag: max(version - seen, 0),
           created_at: created_at
         }}

      {:ok, []} ->
        {:error, :subscription_not_found}

      _ ->
        :error
    end
  end

  defp deserialize(nil, value, _opts), do: value
  defp deserialize(serializer, value, opts), do: serializer.deserialize(value, opts)

  defp sort_dir_sql(:desc), do: "DESC"
  defp sort_dir_sql(_), do: "ASC"

  def event_type_clause(nil, base_params, _next_index), do: {"", base_params}

  def event_type_clause(pattern, base_params, next_index),
    do: {" AND e.event_type ILIKE $#{next_index}", base_params ++ [pattern]}

  defp snapshot_search_clause(nil, base_params, _index), do: {"", base_params}

  defp snapshot_search_clause(term, base_params, index),
    do: {" WHERE source_uuid ILIKE $#{index}", base_params ++ [term]}
end
