defmodule Trogon.Outbox.PostgresOutbox.Publishers.RabbitMQRoutingKeyTest do
  use ExUnit.Case, async: true

  alias Trogon.Outbox.Partition
  alias Trogon.Outbox.Publishers.RabbitMQ

  test "the default routing key fits AMQP's 255 byte limit for every partition" do
    assert :ok = RabbitMQ.validate_routing_keys!(Partition.all(64), [])
  end

  test "a configured routing key over 255 bytes raises" do
    long_key = :binary.copy("x", 256)

    assert_raise ArgumentError, ~r/255 byte limit/, fn ->
      RabbitMQ.validate_routing_keys!(Partition.all(1), routing_key: fn _partition -> long_key end)
    end
  end

  test "a configured routing key at exactly 255 bytes passes" do
    key = :binary.copy("x", 255)
    assert :ok = RabbitMQ.validate_routing_keys!(Partition.all(1), routing_key: fn _partition -> key end)
  end
end
