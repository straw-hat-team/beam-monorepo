defmodule Trogon.Outbox.PostgresOutbox.Publishers.RabbitMQConfirmTimeoutTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.{RabbitMQSupport, TcpProxy}

  @rabbitmq_url RabbitMQSupport.url()

  if is_nil(@rabbitmq_url) do
    @moduletag skip: "set TROGON_OUTBOX_RABBITMQ_URL to a RabbitMQ broker"
  end

  # Falls back to "" so the type checker never sees the nilable value below: this module is
  # skipped at runtime whenever it would matter, so the fallback itself is never dialed.
  @rabbitmq_url @rabbitmq_url || ""

  @moduletag timeout: 10_000

  setup do
    uri = URI.parse(@rabbitmq_url)
    proxy = start_supervised!({TcpProxy, host: uri.host, port: uri.port || 5672})

    proxied_url = %{uri | host: "127.0.0.1", port: TcpProxy.port(proxy)} |> URI.to_string()
    {:ok, connection} = AMQP.Connection.open(proxied_url)
    {:ok, channel} = AMQP.Channel.open(connection)
    queue = RabbitMQSupport.declare_queue!(channel)

    on_exit(fn ->
      try do
        if Process.alive?(connection.pid), do: AMQP.Connection.close(connection)
      catch
        :exit, _reason -> :ok
      end
    end)

    {:ok, proxy: proxy, channel: channel, queue: queue}
  end

  test "a confirm that never arrives times out in milliseconds, not seconds", %{
    proxy: proxy,
    channel: channel,
    queue: queue
  } do
    :ok = AMQP.Confirm.select(channel)
    :ok = AMQP.Basic.return(channel, self())

    # Everything above this point is a normal round trip through the proxy while it still
    # forwards bytes. Pausing it now, before anything new is sent, means the publish below
    # reaches only the client's own socket buffer: the broker never receives it and so never
    # acks it, which times out `wait_for_confirms` deterministically instead of racing a real
    # network round trip.
    #
    # TcpProxy polls its paused flag every 10ms between recv calls, so a recv already in
    # flight when pause/1 returns can still forward whatever arrives for up to that long. The
    # sleep below is well past that poll interval, so the publish below always lands after the
    # proxy has actually stopped forwarding.
    :ok = TcpProxy.pause(proxy)
    Process.sleep(100)

    :ok =
      AMQP.Basic.publish(channel, "", queue, "frozen", mandatory: true, persistent: true, message_id: "test")

    started_at = System.monotonic_time(:millisecond)
    result = AMQP.Confirm.wait_for_confirms(channel, {200, :millisecond})
    elapsed = System.monotonic_time(:millisecond) - started_at

    assert result == :timeout
    assert elapsed >= 150
    assert elapsed < 5_000
  end
end
