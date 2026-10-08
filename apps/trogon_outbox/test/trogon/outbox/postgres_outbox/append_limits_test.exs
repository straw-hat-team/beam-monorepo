defmodule Trogon.Outbox.PostgresOutbox.AppendLimitsTest do
  use Trogon.Outbox.TestSupport.OutboxCase, async: false

  alias Trogon.Outbox.Publisher.Limits

  test "a payload within the limit commits", %{prefix: prefix} do
    assert [_event] = append!(prefix, "source-a", :binary.copy("x", 10), limits: Limits.new!(10))
  end

  test "a payload over :limits raises before anything commits", %{prefix: prefix} do
    assert_raise ArgumentError, ~r/exceeds the publisher's max_payload_size of 10 bytes/, fn ->
      TestRepo.transaction(fn ->
        Trogon.Outbox.append(TestRepo, "source-a", :binary.copy("x", 11), prefix: prefix, limits: Limits.new!(10))
      end)
    end

    assert stored_count(prefix, "source-a") == 0
  end

  test "one oversized payload in a multi-payload append commits none of them", %{prefix: prefix} do
    assert_raise ArgumentError, fn ->
      TestRepo.transaction(fn ->
        Trogon.Outbox.append(TestRepo, "source-a", ["ok", :binary.copy("x", 11)],
          prefix: prefix,
          limits: Limits.new!(10)
        )
      end)
    end

    assert stored_count(prefix, "source-a") == 0
  end

  test "without :limits the default is RabbitMQ 4's broker default max_message_size, 16 MiB", %{prefix: prefix} do
    assert [_event] = append!(prefix, "source-a", "small")
    assert Limits.default().max_payload_size == 16 * 1024 * 1024
  end

  defp stored_count(prefix, source) do
    %Postgrex.Result{rows: [[count]]} =
      SQL.query!(TestRepo, "SELECT count(*) FROM \"#{prefix}\".outbox_events WHERE source = $1", [source])

    count
  end
end
