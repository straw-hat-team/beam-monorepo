defmodule Trogon.Outbox.TestSupport.PoolHealth do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestSupport.ObanJobs

  @doc """
  Blocks until every connection slot in `repo`'s pool can run a trivial query,
  retried until `timeout_ms` elapses. A test that kills backends or blocks new
  connections on a shared pool must prove the pool is fully healthy again
  before returning control to ExUnit, or a later test can inherit a dead
  connection. Raises if the pool is still unhealthy once `timeout_ms` elapses.
  """
  @spec await_healthy!(Ecto.Repo.t(), pos_integer()) :: :ok
  def await_healthy!(repo, timeout_ms \\ 10_000) do
    pool_size = Keyword.fetch!(repo.config(), :pool_size)

    if ObanJobs.eventually(fn -> all_slots_healthy?(repo, pool_size) end, timeout_ms) do
      :ok
    else
      raise "#{inspect(repo)}'s pool did not recover within #{timeout_ms}ms"
    end
  end

  defp all_slots_healthy?(repo, pool_size) do
    1..pool_size
    |> Task.async_stream(fn _ -> SQL.query(repo, "SELECT 1", []) end,
      max_concurrency: pool_size,
      timeout: 2_000,
      on_timeout: :kill_task
    )
    |> Enum.all?(&match?({:ok, {:ok, _}}, &1))
  end
end
