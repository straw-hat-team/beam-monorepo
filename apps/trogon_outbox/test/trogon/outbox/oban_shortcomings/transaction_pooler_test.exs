defmodule Trogon.Outbox.ObanShortcomings.TransactionPoolerTest do
  use ExUnit.Case, async: false

  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs
  alias Trogon.Outbox.TestSupport.ObanReply

  @pooler_url System.get_env("TROGON_OUTBOX_PGBOUNCER_URL")

  if is_nil(@pooler_url) do
    @moduletag skip:
                 "set TROGON_OUTBOX_PGBOUNCER_URL to a PgBouncer in transaction pool mode in front of the test database"
  end

  defmodule PooledRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :trogon_outbox, adapter: Ecto.Adapters.Postgres
  end

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(%Oban.Job{id: id, args: args} = job) do
      ObanReply.send(job, {:published, id, self()})

      if args["wait_after_publish"] do
        receive do
          :finish -> ObanReply.send(job, {:finished, id})
        after
          5_000 -> {:error, :finish_signal_never_arrived}
        end
      end

      :ok
    end
  end

  setup_all do
    Application.put_env(:trogon_outbox, PooledRepo, url: @pooler_url, pool_size: 5)
    on_exit(fn -> Application.delete_env(:trogon_outbox, PooledRepo) end)
  end

  setup do
    ObanJobs.truncate!()
    start_supervised!(PooledRepo)
    :ok
  end

  defp start_pooled_oban!(name, overrides \\ []) do
    start_supervised!({Oban, ObanInstance.opts(name, Keyword.merge([repo: PooledRepo], overrides))})
  end

  defp insert_event!(name, args) do
    args
    |> Map.put("reply_to", ObanReply.encode(self()))
    |> PublishWorker.new()
    |> then(&Oban.insert!(name, &1))
  end

  defp await_isolated!(name) do
    assert ObanJobs.eventually(fn -> Oban.Notifier.status(name) == :isolated end, 10_000)
  end

  test "behind a transaction pooler the notifier never hears its own ping, so it reports itself isolated" do
    start_pooled_oban!(:pooler_status)

    refute ObanJobs.eventually(fn -> Oban.Notifier.status(:pooler_status) in [:solitary, :clustered] end, 7_000)
    assert Oban.Notifier.status(:pooler_status) == :isolated
  end

  test "behind a transaction pooler pause_queue returns :ok and the queue keeps publishing" do
    start_pooled_oban!(:pooler_pause, queues: [relay: 1])
    await_isolated!(:pooler_pause)

    assert :ok = Oban.pause_queue(:pooler_pause, queue: :relay)
    Process.sleep(500)
    refute Oban.check_queue(:pooler_pause, queue: :relay).paused

    %Oban.Job{id: id} = insert_event!(:pooler_pause, %{"event_id" => "evt-1"})
    assert_receive {:published, ^id, _worker}, 5_000
  end

  test "behind a transaction pooler cancelling an executing job marks it cancelled while it keeps running" do
    start_pooled_oban!(:pooler_cancel, queues: [relay: 1])
    await_isolated!(:pooler_cancel)

    %Oban.Job{id: id} = insert_event!(:pooler_cancel, %{"event_id" => "evt-1", "wait_after_publish" => true})
    assert_receive {:published, ^id, worker}, 5_000

    assert :ok = Oban.cancel_job(:pooler_cancel, id)
    assert ObanJobs.state!(id) == "cancelled"

    Process.sleep(500)
    assert Process.alive?(worker)

    send(worker, :finish)
    assert_receive {:finished, ^id}, 5_000
    assert ObanJobs.state!(id) == "cancelled"
  end

  test "named prepared statements and the transaction-scoped unique lock both work through the pooler" do
    start_pooled_oban!(:pooler_unique)

    assert {:ok, %Oban.Job{id: id, conflict?: false}} =
             Oban.insert(:pooler_unique, PublishWorker.new(%{"event_id" => "evt-1"}))

    test_pid = self()

    holder =
      Task.async(fn ->
        PooledRepo.transaction(fn ->
          {:ok, %Oban.Job{conflict?: false}} = Oban.insert(:pooler_unique, PublishWorker.new(%{"event_id" => "evt-2"}))
          send(test_pid, :holding)

          receive do
            :release -> PooledRepo.rollback(:released)
          after
            5_000 -> flunk("the lock holder did not receive the release signal")
          end
        end)
      end)

    assert_receive :holding, 5_000

    assert {:ok, %Oban.Job{id: ^id, conflict?: true}} =
             Oban.insert(:pooler_unique, PublishWorker.new(%{"event_id" => "evt-1"}))

    assert {:ok, %Oban.Job{id: nil, conflict?: true}} =
             Oban.insert(:pooler_unique, PublishWorker.new(%{"event_id" => "evt-2"}))

    send(holder.pid, :release)
    assert {:error, :released} = Task.await(holder, 5_000)
  end
end
