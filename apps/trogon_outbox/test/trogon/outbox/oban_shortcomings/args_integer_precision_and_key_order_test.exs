defmodule Trogon.Outbox.ObanShortcomings.ArgsIntegerPrecisionAndKeyOrderTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule EchoWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{args: args} = job) do
      ObanReply.send(job, {:performed_with, Map.delete(args, "reply_to")})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  test "an integer well beyond 2^53 reaches perform/1 with full precision, not rounded by a float conversion" do
    start_supervised!({Oban, ObanInstance.opts(:integer_precision_node, queues: [relay: 1])})

    beyond_js_safe_integer = 123_456_789_012_345_678_901_234_567_890
    assert beyond_js_safe_integer > trunc(:math.pow(2, 53))

    payload = %{amount: beyond_js_safe_integer}

    %Oban.Job{id: id, args: inserted_args} =
      payload
      |> Map.put(:reply_to, ObanReply.encode(self()))
      |> EchoWorker.new()
      |> then(&Oban.insert!(:integer_precision_node, &1))

    assert inserted_args.amount == beyond_js_safe_integer

    assert_receive {:performed_with, performed_args}, 5_000
    assert performed_args == %{"amount" => beyond_js_safe_integer}

    [[stored_text]] = TestRepo.query!("SELECT (args -> 'amount')::text FROM oban_jobs WHERE id = $1", [id]).rows

    assert stored_text == Integer.to_string(beyond_js_safe_integer)
  end

  test "jsonb storage reorders an object's keys by length then alphabetically, but Oban.Job.args round-trips as a plain Elixir map, so the application never observes any order" do
    start_supervised!({Oban, ObanInstance.opts(:key_order_node, queues: [relay: 1])})

    payload = %{zebra: 1, apple: 2, mm: 3}

    %Oban.Job{id: id} =
      payload
      |> Map.put(:reply_to, ObanReply.encode(self()))
      |> EchoWorker.new()
      |> then(&Oban.insert!(:key_order_node, &1))

    [[stored_keys]] =
      TestRepo.query!(
        "SELECT array_agg(key) FROM oban_jobs, jsonb_each(args) AS kv(key, value) WHERE id = $1 AND key != 'reply_to' GROUP BY id",
        [id]
      ).rows

    refute stored_keys == ["zebra", "apple", "mm"]
    assert stored_keys == ["mm", "apple", "zebra"]

    assert_receive {:performed_with, performed_args}, 5_000
    assert performed_args == %{"zebra" => 1, "apple" => 2, "mm" => 3}
  end
end
