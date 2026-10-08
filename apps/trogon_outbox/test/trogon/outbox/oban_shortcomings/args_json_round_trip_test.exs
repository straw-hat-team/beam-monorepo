defmodule Trogon.Outbox.ObanShortcomings.ArgsJsonRoundTripTest do
  use ExUnit.Case, async: false

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

  test "args reach perform/1 as decoded JSON, not as the terms that were inserted" do
    start_supervised!({Oban, ObanInstance.opts(:args_node, queues: [relay: 1])})

    occurred_at = ~U[2026-01-02 03:04:05.000000Z]
    payload = %{status: :shipped, occurred_at: occurred_at, lines: %{1 => "sku-1"}}

    %Oban.Job{args: inserted_args} =
      payload
      |> Map.put(:reply_to, ObanReply.encode(self()))
      |> EchoWorker.new()
      |> then(&Oban.insert!(:args_node, &1))

    assert Map.delete(inserted_args, :reply_to) == payload

    assert_receive {:performed_with, performed_args}, 5_000

    assert performed_args == %{
             "status" => "shipped",
             "occurred_at" => "2026-01-02T03:04:05.000000Z",
             "lines" => %{"1" => "sku-1"}
           }

    refute performed_args == payload
  end
end
