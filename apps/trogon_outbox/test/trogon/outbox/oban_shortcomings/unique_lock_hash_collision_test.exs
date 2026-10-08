defmodule Trogon.Outbox.ObanShortcomings.UniqueLockHashCollisionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo
  alias Trogon.Outbox.TestSupport.ObanInstance
  alias Trogon.Outbox.TestSupport.ObanJobs

  @name :unique_hash_collision_node

  defmodule PublishWorker do
    @moduledoc false
    use Oban.Worker, queue: :relay, unique: [fields: [:args, :worker]]

    @impl Oban.Worker
    def perform(_job), do: :ok
  end

  # Stands in for the repo so the Basic engine computes the advisory lock key without touching
  # the database. The hashed term embeds the path Oban was compiled from, so a colliding pair
  # differs between builds and is searched for on every run instead of being hardcoded.
  defmodule LockKeyProbe do
    @moduledoc false

    def config, do: []

    def transaction(fun, _opts), do: {:ok, fun.()}

    def query("SELECT pg_try_advisory_xact_lock($1)", [lock_key], _opts) do
      Process.put(__MODULE__, lock_key)
      {:ok, %{rows: [[false]]}}
    end

    def get_dynamic_repo, do: __MODULE__
    def put_dynamic_repo(_repo), do: __MODULE__
  end

  setup do
    ObanJobs.truncate!()
    start_supervised!({Oban, ObanInstance.opts(@name)})
    :ok
  end

  defp probe_lock_key(conf, event_id) do
    {:ok, %Oban.Job{conflict?: true}} = Oban.Engines.Basic.insert_job(conf, new_event(event_id), [])
    Process.get(LockKeyProbe)
  end

  defp colliding_event_ids do
    conf = Oban.Config.new(repo: LockKeyProbe, testing: :disabled, name: :unique_hash_probe)

    Enum.reduce_while(1..1_000_000, %{}, fn sequence, seen ->
      event_id = "evt-#{sequence}"
      lock_key = probe_lock_key(conf, event_id)

      case seen do
        %{^lock_key => earlier_event_id} -> {:halt, {earlier_event_id, event_id}}
        %{} -> {:cont, Map.put(seen, lock_key, event_id)}
      end
    end)
  end

  defp new_event(event_id), do: PublishWorker.new(%{"event_id" => event_id})

  defp insert_event(event_id), do: Oban.insert(@name, new_event(event_id))

  defp held_lock_keys do
    TestRepo
    |> SQL.query!(
      "SELECT (classid::bigint << 32) | objid::bigint FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid()"
    )
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp stored_event_ids do
    TestRepo.all(Oban.Job) |> Enum.map(& &1.args["event_id"]) |> Enum.sort()
  end

  test "two different events whose unique lock keys collide cannot be inserted at the same time, and the second is dropped" do
    {first, second} = colliding_event_ids()
    assert first != second

    test_pid = self()

    holder =
      Task.async(fn ->
        TestRepo.transaction(fn ->
          {:ok, %Oban.Job{conflict?: false}} = insert_event(first)
          send(test_pid, {:inserted, held_lock_keys()})

          receive do
            :commit -> :ok
          after
            5_000 -> flunk("the first insert did not receive the commit signal")
          end
        end)
      end)

    assert_receive {:inserted, [first_lock_key]}, 5_000

    assert {:ok, %Oban.Job{id: nil, conflict?: true}} = insert_event(second)

    send(holder.pid, :commit)
    Task.await(holder, 5_000)

    assert stored_event_ids() == [first]
    assert database_lock_key!(second) == first_lock_key

    assert {:ok, %Oban.Job{conflict?: false}} = insert_event(second)
    assert stored_event_ids() == Enum.sort([first, second])
  end

  defp database_lock_key!(event_id) do
    {:error, [lock_key]} =
      TestRepo.transaction(fn ->
        {:ok, %Oban.Job{}} = insert_event(event_id)
        TestRepo.rollback(held_lock_keys())
      end)

    lock_key
  end
end
