defmodule Trogon.Outbox.ObanShortcomings.ScheduledAtClockSourceTest do
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

  test "a job inserted without a scheduling option has no scheduled_at in its changeset, so the database default supplies it at insert" do
    changeset = PublishWorker.new(%{"sequence" => 1})
    refute Map.has_key?(changeset.changes, :scheduled_at)

    start_supervised!({Oban, ObanInstance.opts(:scheduled_at_default_node, queues: [])})
    before_insert = DateTime.utc_now()
    %Oban.Job{id: id} = Oban.insert!(:scheduled_at_default_node, changeset)
    after_insert = DateTime.utc_now()

    scheduled_at = ObanJobs.fetch(id).scheduled_at
    assert DateTime.compare(scheduled_at, before_insert) != :lt
    assert DateTime.compare(scheduled_at, after_insert) != :gt
  end

  test "a later job with an explicit scheduled_at computed from a clock reading behind real time is fetched ahead of an earlier job that used the database clock" do
    start_supervised!({Oban, ObanInstance.opts(:scheduled_at_skew_node, queues: [relay: [limit: 1, paused: true]])})
    reply_to = ObanReply.encode(self())

    %Oban.Job{id: first} =
      %{"source" => "order-1", "sequence" => 1, "reply_to" => reply_to}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:scheduled_at_skew_node, &1))

    skewed_scheduled_at = DateTime.add(DateTime.utc_now(), -10, :second)

    second_changeset =
      %{"source" => "order-1", "sequence" => 2, "reply_to" => reply_to}
      |> PublishWorker.new(scheduled_at: skewed_scheduled_at)

    assert Ecto.Changeset.get_change(second_changeset, :state) == "scheduled"

    %Oban.Job{id: second} = Oban.insert!(:scheduled_at_skew_node, second_changeset)

    assert second > first

    first_scheduled_at = ObanJobs.fetch(first).scheduled_at
    second_scheduled_at = ObanJobs.fetch(second).scheduled_at
    assert DateTime.compare(second_scheduled_at, first_scheduled_at) == :lt

    assert ObanJobs.eventually(fn -> ObanJobs.state!(second) == "available" end)

    :ok = ObanInstance.await_notifier!(:scheduled_at_skew_node)
    :ok = Oban.resume_queue(:scheduled_at_skew_node, queue: :relay)

    published =
      for _sequence <- [1, 2] do
        receive do
          {:published, sequence} -> sequence
        after
          5_000 -> flunk("a job was not published in time")
        end
      end

    assert published == [2, 1]
  end
end
