defmodule Trogon.Outbox.PostgresOutbox.RelayStartValidationTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Publisher.Limits
  alias Trogon.Outbox.Relay

  defmodule RoutingKeyPublisher do
    @moduledoc false
    @behaviour Trogon.Outbox.Publisher

    @impl Trogon.Outbox.Publisher
    def publish(_batch, _opts), do: :ok

    @doc "Stands in for a publisher's own routing-key check, rejecting any key over :max_routing_key_size."
    def validate_routing_keys!(partitions, opts) do
      max = Keyword.fetch!(opts, :max_routing_key_size)

      Enum.each(partitions, fn partition ->
        key = to_string(partition)

        if byte_size(key) > max do
          raise ArgumentError,
                "the routing key for partition #{partition} is #{byte_size(key)} bytes, over the #{max} byte limit"
        end
      end)
    end
  end

  defmodule SizedPublisher do
    @moduledoc false
    @behaviour Trogon.Outbox.Publisher

    @impl Trogon.Outbox.Publisher
    def publish(_batch, _opts), do: :ok

    @impl Trogon.Outbox.Publisher
    def limits(opts), do: Limits.new!(Keyword.fetch!(opts, :max_payload_size))
  end

  test "fails to start when a partition's routing key is too long", %{prefix: prefix} do
    Process.flag(:trap_exit, true)

    result =
      Relay.start_link(
        repo: TestRepo,
        prefix: prefix,
        relay: "test",
        publisher: {RoutingKeyPublisher, max_routing_key_size: 0}
      )

    assert {:error, reason} = result
    assert {%ArgumentError{message: message}, _stacktrace} = reason
    assert message =~ "byte limit"
  end

  test "fails to start when broker_max_message_size is smaller than the publisher's max_payload_size", %{
    prefix: prefix
  } do
    Process.flag(:trap_exit, true)

    result =
      Relay.start_link(
        repo: TestRepo,
        prefix: prefix,
        relay: "test",
        publisher: {SizedPublisher, max_payload_size: 1_000},
        broker_max_message_size: 500
      )

    assert {:error, reason} = result
    assert {%ArgumentError{message: message}, _stacktrace} = reason
    assert message =~ "max_message_size"
  end

  test "starts without checking the publisher's limits when broker_max_message_size is unset", %{prefix: prefix} do
    relay =
      start_supervised!(
        {Relay, repo: TestRepo, prefix: prefix, relay: "test", publisher: {SizedPublisher, max_payload_size: 1_000}}
      )

    assert Process.alive?(relay)
  end
end
