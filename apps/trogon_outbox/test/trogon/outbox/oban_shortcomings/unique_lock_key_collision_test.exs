defmodule Trogon.Outbox.ObanShortcomings.UniqueLockKeyCollisionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  setup do
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(:unique_lock_node)})
    :ok
  end

  defp insert_event(event_id), do: Oban.insert(:unique_lock_node, PublishWorker.new(%{"event_id" => event_id}))

  defp unique_lock_key!(event_id) do
    {:error, lock_keys} =
      TestRepo.transaction(fn ->
        {:ok, %Oban.Job{conflict?: false}} = insert_event(event_id)

        %Postgrex.Result{rows: rows} =
          SQL.query!(
            TestRepo,
            "SELECT (classid::bigint << 32) | objid::bigint FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
          )

        TestRepo.rollback(List.flatten(rows))
      end)

    [lock_key] = lock_keys
    lock_key
  end

  defp hold_advisory_lock(lock_key) do
    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          SQL.query!(TestRepo, "SELECT pg_advisory_xact_lock($1)", [lock_key])
          send(test_pid, :locked)

          receive do
            :release -> :ok
          after
            5_000 -> flunk("the lock holder did not receive the release signal")
          end
        end)
      end)

    receive do
      :locked -> holder
    after
      5_000 -> flunk("the lock holder did not take the advisory lock in time")
    end
  end

  test "a unique insert is reported as a conflict and never stored while an unrelated session holds an advisory lock with the same key" do
    lock_key = unique_lock_key!("evt-1")
    assert ObanJobs.count!() == 0

    holder = hold_advisory_lock(lock_key)

    assert {:ok, %Oban.Job{id: nil, conflict?: true}} = insert_event("evt-1")
    assert ObanJobs.count!() == 0

    send(holder.pid, :release)
    Task.await(holder, 5_000)

    assert {:ok, %Oban.Job{conflict?: false}} = insert_event("evt-1")
    assert ObanJobs.count!() == 1
  end

  test "the unique lock key lives in a space of at most 2 to the power of 28 values, far narrower than a bigint advisory lock" do
    lock_keys = for sequence <- 1..50, do: unique_lock_key!("evt-#{sequence}")

    assert Enum.all?(lock_keys, &(&1 >= 0 and &1 < Integer.pow(2, 28)))
  end
end
