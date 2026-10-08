defmodule Trogon.Outbox.Relay do
  @moduledoc """
  Publishes outbox events to a `Trogon.Outbox.Publisher`, keeping commit order per source.

  A relay opens one dedicated connection and takes a session-level advisory lock per partition on
  it, so only one relay with the same `:relay` name consumes a partition at a time. Partitions it
  cannot lock are retried every `:lock_interval`, which makes any other relay with the same name a
  standby. When the connection is lost the relay stops, and its locks are released with the
  session.

  It reads events below the snapshot watermark, `pg_snapshot_xmin(pg_current_snapshot())`, so a
  transaction that commits late is never skipped, and polls with a backoff that doubles from
  `:min_poll_interval` to `:max_poll_interval` while there is nothing to publish. A partition
  whose publish fails backs off the same way on its own, without delaying the other partitions.

  At startup, once partitions are resolved and before the first poll, a publisher module that
  exports `validate_routing_keys!/2` (`Trogon.Outbox.Publishers.RabbitMQ` does) is called with
  every partition and its own options, so an oversized routing key fails loudly immediately
  instead of mid-flight. Setting `:broker_max_message_size` checks the same way, against a
  publisher's optional `limits/1` callback, so a `:max_payload_size` configured larger than the
  broker actually accepts fails at startup too.

  ## Telemetry

  On its own `:telemetry_interval`, independent of the poll backoff, a relay reports:

    * `[:trogon, :outbox, :cursor, :lag]` - once per held partition, measurements `:count` (events
      below the watermark it has not published yet) and `:oldest_event_age_ms`, metadata
      `:relay` and `:partition`.
    * `[:trogon, :outbox, :watermark, :holdback]` - measurement `:age_ms`, how long the oldest
      other open transaction in the cluster has held the watermark back, metadata `:relay`.

  On every lock change:

    * `[:trogon, :outbox, :lock, :acquired]` - measurement `:count`, metadata `:relay` and
      `:partitions`, the newly locked partition numbers.
    * `[:trogon, :outbox, :lock, :lost]` - measurement `:count`, the partitions held at the time,
      metadata `:relay` and `:backend_pid`. Fires right before the relay stops with `:lock_lost`.

  `held_partitions/1` and `health/1` read the same state and queries on demand, for a health
  check that does not need a telemetry handler wired up.

  ## Options

    * `:repo` - the Ecto repo whose configuration the dedicated connection uses. Required.
    * `:relay` - the relay name. Cursors and locks are kept per relay name and partition, so
      relays with different names each publish every event. Required.
    * `:publisher` - a `Trogon.Outbox.Publisher` module, or `{module, opts}`. Required.
    * `:prefix` - the schema holding the outbox tables, `"public"` by default.
    * `:partitions` - `:all` or a list of partition numbers to consume, `:all` by default.
    * `:batch_size` - the most events read per partition per poll, 500 by default.
    * `:min_poll_interval` and `:max_poll_interval` - in milliseconds, 10 and 1000 by default.
    * `:lock_interval` - how often to retry unheld partitions, in milliseconds, 1000 by default.
    * `:telemetry_interval` - how often to report lag and watermark holdback, in milliseconds,
      5000 by default. See "Telemetry" above.
    * `:broker_max_message_size` - the broker's own maximum message size, in bytes, to check the
      publisher's limits against at startup. `nil` by default, which skips the check. See
      `Trogon.Outbox.Publisher.Limits.check_broker_max_message_size!/2`.
    * `:connection` - Postgrex options merged over the repo configuration.
    * `:pooler_guard` - whether to check, at startup only, that the connection does not go
      through a transaction-mode pooler, `false` by default since the check forces connection
      contention and adds connections of its own. See `Trogon.Outbox.Relay.PoolerGuard`.
    * `:name` - the process name.
  """

  use GenServer

  require Logger

  alias Trogon.Outbox.{Batch, Partition, Postgres, PostgresVersion}
  alias Trogon.Outbox.Publisher.Limits
  alias Trogon.Outbox.Relay.{Health, PoolerGuard, Store}

  @connection_keys [
    :hostname,
    :endpoints,
    :port,
    :database,
    :username,
    :password,
    :socket,
    :socket_dir,
    :ssl,
    :ssl_opts,
    :socket_options,
    :parameters,
    :connect_timeout,
    :handshake_timeout,
    :timeout,
    :prepare,
    :types
  ]

  @type option ::
          {:repo, Ecto.Repo.t()}
          | {:relay, String.t()}
          | {:publisher, module() | {module(), keyword()}}
          | {:prefix, String.t()}
          | {:partitions, :all | [non_neg_integer()]}
          | {:batch_size, pos_integer()}
          | {:min_poll_interval, non_neg_integer()}
          | {:max_poll_interval, pos_integer()}
          | {:lock_interval, pos_integer()}
          | {:telemetry_interval, pos_integer()}
          | {:broker_max_message_size, pos_integer()}
          | {:connection, keyword()}
          | {:pooler_guard, boolean()}
          | {:name, GenServer.name()}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :relay)}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc "The partitions this relay currently holds the lock for."
  @spec held_partitions(GenServer.server()) :: [Partition.t()]
  def held_partitions(server), do: GenServer.call(server, :held_partitions)

  @doc "A point-in-time read of held partitions, lag and watermark holdback. See `Trogon.Outbox.Relay.Health`."
  @spec health(GenServer.server()) :: Health.t()
  def health(server), do: GenServer.call(server, :health)

  @doc "Wakes the relay to poll now instead of waiting for its backoff."
  @spec poll(GenServer.server()) :: :ok
  def poll(server), do: GenServer.cast(server, :poll)

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    repo = Keyword.fetch!(opts, :repo)
    relay = relay_name!(Keyword.fetch!(opts, :relay))
    prefix = Postgres.validate_prefix!(Keyword.get(opts, :prefix, "public"))
    {publisher, publisher_opts} = publisher!(Keyword.fetch!(opts, :publisher))

    conn_opts = connection_opts(repo, Keyword.get(opts, :connection, []))
    {:ok, conn} = Postgrex.start_link(conn_opts)
    if Keyword.get(opts, :pooler_guard, false), do: PoolerGuard.ensure_not_pooled!(conn, conn_opts)
    conn |> PostgresVersion.fetch!() |> PostgresVersion.ensure_supported!()
    backend_pid = Store.backend_pid!(conn)
    relay_id = Store.relay_id!(conn, prefix, relay)

    partitions =
      case Keyword.get(opts, :partitions, :all) do
        :all -> Partition.all(Store.partition_count!(conn, prefix))
        partitions -> Enum.map(partitions, &Partition.new!/1)
      end

    validate_publisher!(publisher, publisher_opts, partitions, Keyword.get(opts, :broker_max_message_size))

    state = %{
      conn: conn,
      backend_pid: backend_pid,
      relay: relay,
      relay_id: relay_id,
      prefix: prefix,
      publisher: publisher,
      publisher_opts: publisher_opts,
      partitions: partitions,
      held: %{},
      retries: %{},
      batch_size: Keyword.get(opts, :batch_size, 500),
      min_poll_interval: Keyword.get(opts, :min_poll_interval, 10),
      max_poll_interval: Keyword.get(opts, :max_poll_interval, 1_000),
      lock_interval: Keyword.get(opts, :lock_interval, 1_000),
      telemetry_interval: Keyword.get(opts, :telemetry_interval, 5_000),
      poll_interval: Keyword.get(opts, :min_poll_interval, 10),
      locked_at: nil,
      timer: nil,
      telemetry_timer: nil
    }

    {:ok, state |> schedule(0) |> schedule_telemetry()}
  end

  @impl GenServer
  def handle_call(:held_partitions, _from, state) do
    {:reply, state.held |> Map.keys() |> Enum.sort_by(& &1.value), state}
  end

  def handle_call(:health, _from, state) do
    health = %Health{
      held: state.held |> Map.keys() |> Enum.sort_by(& &1.value),
      expected: Enum.sort_by(state.partitions, & &1.value),
      lag: Store.lag!(state.conn, state.prefix, state.held),
      watermark_holdback_ms: Store.watermark_holdback_ms!(state.conn)
    }

    {:reply, health, state}
  end

  @impl GenServer
  def handle_cast(:poll, state), do: {:noreply, schedule(%{state | poll_interval: state.min_poll_interval}, 0)}

  @impl GenServer
  def handle_info(:tick, state) do
    state = %{state | timer: nil}

    with {:ok, state} <- maybe_lock(state),
         {:ok, activity, state} <- publish_held(state) do
      {:noreply, schedule_after(state, activity)}
    else
      {:error, :lock_lost} ->
        :telemetry.execute([:trogon, :outbox, :lock, :lost], %{count: map_size(state.held)}, %{
          relay: state.relay,
          backend_pid: state.backend_pid
        })

        {:stop, :lock_lost, state}
    end
  end

  def handle_info(:telemetry_tick, state) do
    Enum.each(Store.lag!(state.conn, state.prefix, state.held), fn {partition, lag} ->
      :telemetry.execute([:trogon, :outbox, :cursor, :lag], Map.from_struct(lag), %{
        relay: state.relay,
        partition: partition.value
      })
    end)

    :telemetry.execute(
      [:trogon, :outbox, :watermark, :holdback],
      %{age_ms: Store.watermark_holdback_ms!(state.conn)},
      %{relay: state.relay}
    )

    {:noreply, schedule_telemetry(state)}
  end

  def handle_info({:EXIT, conn, reason}, %{conn: conn} = state), do: {:stop, {:connection_down, reason}, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}
  def handle_info({:disconnected, _pid}, state), do: {:stop, :connection_lost, state}
  def handle_info({:disconnected, _pid, _tag}, state), do: {:stop, :connection_lost, state}
  def handle_info({:connected, _pid}, state), do: {:noreply, state}
  def handle_info({:connected, _pid, _tag}, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{conn: conn}) do
    if Process.alive?(conn), do: GenServer.stop(conn, :normal, 5_000)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp maybe_lock(state) do
    unheld = Enum.reject(state.partitions, &Map.has_key?(state.held, &1))
    now = System.monotonic_time(:millisecond)

    if unheld != [] and (state.locked_at == nil or now - state.locked_at >= state.lock_interval) do
      lock(%{state | locked_at: now}, unheld)
    else
      {:ok, state}
    end
  end

  defp lock(state, unheld) do
    case Store.try_lock!(state.conn, state.relay_id, unheld) do
      {backend_pid, _locked} when backend_pid != state.backend_pid ->
        {:error, :lock_lost}

      {_backend_pid, []} ->
        {:ok, state}

      {_backend_pid, locked} ->
        :telemetry.execute([:trogon, :outbox, :lock, :acquired], %{count: length(locked)}, %{
          relay: state.relay,
          partitions: Enum.map(locked, & &1.value)
        })

        cursors = Store.load_cursors!(state.conn, state.prefix, state.relay, locked)
        {:ok, %{state | held: Map.merge(state.held, cursors)}}
    end
  end

  defp publish_held(%{held: held} = state) when map_size(held) == 0, do: {:ok, :idle, state}

  defp publish_held(state) do
    now = System.monotonic_time(:millisecond)
    due = Map.reject(state.held, fn {partition, _cursor} -> retrying?(state, partition, now) end)

    batches =
      if due == %{}, do: [], else: Store.read!(state.conn, state.prefix, due, state.batch_size, state.backend_pid)

    {advances, failed, activity} =
      Enum.reduce(batches, {%{}, [], :idle}, fn {partition, events}, {advances, failed, activity} ->
        batch = Batch.new(state.relay, partition, events)

        case publish(state, batch) do
          :ok -> {Map.put(advances, partition, Batch.cursor(batch)), failed, merge_activity(activity, batch, state)}
          {:error, _reason} -> {advances, [partition | failed], activity}
        end
      end)

    case Store.advance!(state.conn, state.prefix, state.relay, advances, state.backend_pid) do
      :ok ->
        held = Map.merge(state.held, advances)
        {:ok, activity, %{state | held: held, retries: retries(state, Map.keys(advances), failed, now)}}

      {:error, :lock_lost} ->
        {:error, :lock_lost}
    end
  end

  defp retrying?(state, partition, now) do
    case Map.fetch(state.retries, partition) do
      {:ok, {_interval, retry_at}} -> retry_at > now
      :error -> false
    end
  end

  defp retries(state, succeeded, failed, now) do
    failed
    |> Enum.reduce(Map.drop(state.retries, succeeded), fn partition, retries ->
      interval =
        case Map.fetch(retries, partition) do
          {:ok, {interval, _retry_at}} -> min(interval * 2, state.max_poll_interval)
          :error -> max(state.min_poll_interval, 1)
        end

      Map.put(retries, partition, {interval, now + interval})
    end)
  end

  defp publish(state, batch) do
    case state.publisher.publish(batch, state.publisher_opts) do
      :ok ->
        :ok

      {:error, reason} = error ->
        log_failure(batch, reason)
        error

      other ->
        log_failure(batch, {:unexpected_return, other})
        {:error, {:unexpected_return, other}}
    end
  rescue
    exception ->
      log_failure(batch, exception)
      {:error, exception}
  catch
    kind, reason ->
      log_failure(batch, {kind, reason})
      {:error, {kind, reason}}
  end

  defp log_failure(batch, reason) do
    Logger.warning(
      "Trogon.Outbox.Relay #{batch.relay} failed to publish #{Batch.size(batch)} events of partition " <>
        "#{batch.partition}, the batch will be retried: #{inspect(reason)}"
    )
  end

  defp merge_activity(_activity, batch, state) when length(batch.events) >= state.batch_size, do: :full
  defp merge_activity(:full, _batch, _state), do: :full
  defp merge_activity(_activity, _batch, _state), do: :some

  defp schedule_after(state, :full), do: schedule(%{state | poll_interval: state.min_poll_interval}, 0)

  defp schedule_after(state, :some),
    do: schedule(%{state | poll_interval: state.min_poll_interval}, state.min_poll_interval)

  defp schedule_after(state, :idle) do
    interval = state.poll_interval
    schedule(%{state | poll_interval: min(max(interval * 2, 1), state.max_poll_interval)}, interval)
  end

  defp schedule(state, interval) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :tick, interval)}
  end

  defp schedule_telemetry(state) do
    if state.telemetry_timer, do: Process.cancel_timer(state.telemetry_timer)
    %{state | telemetry_timer: Process.send_after(self(), :telemetry_tick, state.telemetry_interval)}
  end

  defp connection_opts(repo, overrides) do
    repo.config()
    |> Keyword.take(@connection_keys)
    |> Keyword.merge(overrides)
    |> Keyword.update(:parameters, relay_parameters(), &Keyword.merge(&1, relay_parameters()))
    |> Keyword.merge(pool_size: 1, backoff_type: :stop, connection_listeners: [self()])
  end

  defp relay_parameters, do: [application_name: "trogon_outbox_relay", synchronous_commit: "off"]

  defp relay_name!(relay) when is_binary(relay) and byte_size(relay) > 0, do: relay
  defp relay_name!(relay), do: raise(ArgumentError, "the relay name must be a non-empty string, got: #{inspect(relay)}")

  defp publisher!({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp publisher!(module) when is_atom(module), do: {module, []}

  defp validate_publisher!(publisher, publisher_opts, partitions, broker_max_message_size) do
    if function_exported?(publisher, :validate_routing_keys!, 2) do
      publisher.validate_routing_keys!(partitions, publisher_opts)
    end

    if broker_max_message_size && function_exported?(publisher, :limits, 1) do
      Limits.check_broker_max_message_size!(publisher.limits(publisher_opts), broker_max_message_size)
    end

    :ok
  end
end
