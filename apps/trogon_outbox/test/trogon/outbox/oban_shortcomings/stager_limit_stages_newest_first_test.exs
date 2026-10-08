defmodule Trogon.Outbox.ObanShortcomings.StagerLimitStagesNewestFirstTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"sequence" => sequence}} = job) do
      ObanReply.send(job, {:published, sequence})
      :ok
    end
  end

  setup do
    ObanJobs.truncate!()
    :ok
  end

  defp insert_due_events!(name, sequences) do
    reply_to = ObanReply.encode(self())
    now = DateTime.utc_now()

    for sequence <- sequences do
      due_at = DateTime.add(now, sequence - 60, :second)

      %{"source" => "order-1", "sequence" => sequence, "reply_to" => reply_to}
      |> PublishWorker.new(scheduled_at: due_at)
      |> then(&Oban.insert!(name, &1))
    end
  end

  defp published_order(count) do
    for _sequence <- 1..count do
      receive do
        {:published, sequence} -> sequence
      after
        5_000 -> flunk("a staged job was not published in time")
      end
    end
  end

  test "when more jobs are due than the stager limit, the newest are staged and published first" do
    start_supervised!({Oban, ObanInstance.opts(:stager_limit, queues: [relay: 1], stager: [interval: 500, limit: 2])})

    insert_due_events!(:stager_limit, 1..4)

    assert published_order(4) == [3, 4, 1, 2]
  end

  test "with a stager limit above the number of due jobs, they publish in scheduled order" do
    start_supervised!({Oban, ObanInstance.opts(:stager_no_limit, queues: [relay: 1], stager: [interval: 500])})

    insert_due_events!(:stager_no_limit, 1..4)

    assert published_order(4) == [1, 2, 3, 4]
  end
end
