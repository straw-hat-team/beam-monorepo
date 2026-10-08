defmodule Trogon.Outbox.Design.NotifyOrderingTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  setup do
    listener = start_supervised!({Postgrex.Notifications, TestRepo.config()})
    suffix = System.unique_integer([:positive])
    channel_a = "design_notify_a_#{suffix}"
    channel_b = "design_notify_b_#{suffix}"
    Postgrex.Notifications.listen!(listener, channel_a)
    Postgrex.Notifications.listen!(listener, channel_b)

    %{channel_a: channel_a, channel_b: channel_b}
  end

  test "a listener receives no notification from a transaction that has not committed yet", %{
    channel_a: channel_a,
    channel_b: channel_b
  } do
    held = held_notifier(channel_a, "a")
    assert_receive :notified, 5_000

    notify!(channel_b, "b")

    assert_receive {:notification, _pid, _ref, ^channel_b, "b"}, 5_000
    refute_received {:notification, _pid, _ref, ^channel_a, _payload}

    send(held.pid, :release)
    assert {:ok, :ok} = Task.await(held, 5_000)

    assert_receive {:notification, _pid, _ref, ^channel_a, "a"}, 5_000
  end

  test "notifications are delivered in commit order, not in the order NOTIFY was issued", %{
    channel_a: channel_a,
    channel_b: channel_b
  } do
    held = held_notifier(channel_a, "issued-first")
    assert_receive :notified, 5_000

    notify!(channel_b, "issued-second")

    send(held.pid, :release)
    assert {:ok, :ok} = Task.await(held, 5_000)

    notify!(channel_b, "issued-third")

    assert collect_notifications(3) == [
             {channel_b, "issued-second"},
             {channel_a, "issued-first"},
             {channel_b, "issued-third"}
           ]
  end

  test "a notification from a rolled-back transaction is never delivered", %{
    channel_a: channel_a,
    channel_b: channel_b
  } do
    held = held_notifier(channel_a, "rolled-back")
    assert_receive :notified, 5_000

    send(held.pid, :rollback)
    assert {:error, :aborted} = Task.await(held, 5_000)

    notify!(channel_b, "committed")

    assert_receive {:notification, _pid, _ref, ^channel_b, "committed"}, 5_000
    refute_received {:notification, _pid, _ref, ^channel_a, _payload}
  end

  defp notify!(channel, payload) do
    SQL.query!(TestRepo, "SELECT pg_notify($1, $2)", [channel, payload])
    :ok
  end

  defp held_notifier(channel, payload) do
    test_pid = self()

    Task.async(fn ->
      TestRepo.transaction(fn ->
        notify!(channel, payload)
        send(test_pid, :notified)

        receive do
          :release -> :ok
          :rollback -> TestRepo.rollback(:aborted)
        after
          5_000 -> flunk("the notifying transaction did not receive the release signal")
        end
      end)
    end)
  end

  defp collect_notifications(count) do
    Enum.map(1..count, fn _ ->
      receive do
        {:notification, _pid, _ref, channel, payload} -> {channel, payload}
      after
        5_000 -> flunk("expected #{count} notifications in time")
      end
    end)
  end
end
