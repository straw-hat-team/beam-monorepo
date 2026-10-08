defmodule Trogon.Outbox.ObanShortcomings.NotifierPayloadLimitTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  @name :notifier_payload_node

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "a notify payload under the 8000 byte Postgres limit is delivered to a listener" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [])})
    :ok = ObanInstance.await_notifier!(@name)

    :ok = Oban.Notifier.listen(@name, :payload_limit)

    data = :crypto.strong_rand_bytes(5_800) |> Base.encode64()
    assert byte_size(Oban.Notifier.encode(%{data: data})) < 8_000

    assert :ok = Oban.Notifier.notify(@name, :payload_limit, %{data: data})

    assert_receive {:notification, :payload_limit, %{"data" => ^data}}, 2_000
  end

  test "a notify payload over the 8000 byte Postgres limit still returns :ok, but Postgres rejects the NOTIFY and nothing is delivered" do
    start_supervised!({Oban, ObanInstance.opts(@name, queues: [])})
    :ok = ObanInstance.await_notifier!(@name)

    :ok = Oban.Notifier.listen(@name, :payload_limit)

    data = :crypto.strong_rand_bytes(6_300) |> Base.encode64()
    assert byte_size(Oban.Notifier.encode(%{data: data})) > 8_000

    assert :ok = Oban.Notifier.notify(@name, :payload_limit, %{data: data})

    refute_receive {:notification, :payload_limit, _}, 2_000

    small_data = "still alive"
    assert :ok = Oban.Notifier.notify(@name, :payload_limit, %{data: small_data})
    assert_receive {:notification, :payload_limit, %{"data" => ^small_data}}, 2_000
  end
end
