defmodule Trogon.Outbox.OrderingGaps.BrokerReorderingModelTest do
  @moduledoc """
  This is a model of the transport, not a broker integration test: it spawns
  two plain Elixir processes standing in for competing consumers and proves
  that round-robin dispatch plus different processing latency is enough, on
  its own, to reorder handling relative to delivery order. It does not talk
  to any message broker.
  """

  use ExUnit.Case, async: false

  test "round-robin dispatch to two consumers with different latency reorders handling vs delivery (model of the transport, not a broker integration test)" do
    test_pid = self()

    consumer = fn delay_ms ->
      spawn_link(fn ->
        loop = fn loop ->
          receive do
            {:handle, id} ->
              if delay_ms > 0, do: Process.sleep(delay_ms)
              send(test_pid, {:handled, id})
              loop.(loop)

            :stop ->
              :ok
          end
        end

        loop.(loop)
      end)
    end

    slow_consumer = consumer.(60)
    fast_consumer = consumer.(0)
    consumers = {slow_consumer, fast_consumer}

    deliveries = [1, 2, 3, 4]

    Enum.each(deliveries, fn id ->
      target = if rem(id, 2) == 1, do: elem(consumers, 0), else: elem(consumers, 1)
      send(target, {:handle, id})
    end)

    handled =
      for _delivery <- deliveries do
        receive do
          {:handled, id} -> id
        after
          5_000 -> flunk("a consumer did not report handling a delivery in time")
        end
      end

    send(slow_consumer, :stop)
    send(fast_consumer, :stop)

    assert deliveries == [1, 2, 3, 4]
    assert handled == [2, 4, 1, 3]
    assert handled != deliveries
  end
end
