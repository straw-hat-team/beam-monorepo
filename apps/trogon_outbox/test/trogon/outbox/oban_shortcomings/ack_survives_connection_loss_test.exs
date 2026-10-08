defmodule Trogon.Outbox.ObanShortcomings.AckSurvivesConnectionLossTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply
  alias Trogon.Outbox.TestSupport.PoolHealth

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay

    @impl Oban.Worker
    def perform(%Oban.Job{id: id} = job) do
      ObanReply.send(job, {:published, id, self()})

      receive do
        :ack -> :ok
      after
        5_000 -> {:error, :ack_signal_never_arrived}
      end
    end
  end

  setup do
    ObanJobs.truncate!()
    on_exit(fn -> PoolHealth.await_healthy!(TestRepo) end)
    :ok
  end

  defp terminate_other_backends! do
    SQL.query!(
      TestRepo,
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid()"
    )
  end

  defp state_tolerating_disconnects(id) do
    ObanJobs.state!(id)
  rescue
    DBConnection.ConnectionError -> nil
    Postgrex.Error -> nil
  end

  test "a job whose connections are all terminated between publish and ack is still completed once the database is reachable" do
    start_supervised!({Oban, ObanInstance.opts(:ack_connection_loss, queues: [relay: 1])})

    %Oban.Job{id: id} =
      %{"source" => "order-1", "reply_to" => ObanReply.encode(self())}
      |> PublishWorker.new()
      |> then(&Oban.insert!(:ack_connection_loss, &1))

    assert_receive {:published, ^id, worker}, 5_000

    terminate_other_backends!()
    send(worker, :ack)

    ObanJobs.eventually(fn -> state_tolerating_disconnects(id) == "completed" end, 5_000)

    job = ObanJobs.fetch(id)

    assert job.state == "completed",
           "expected job #{id} to complete within 5s, got state=#{inspect(job.state)} " <>
             "attempt=#{job.attempt} errors=#{inspect(job.errors)}"

    refute_receive {:published, ^id, _worker}, 500
    assert job.attempt == 1
  end
end
