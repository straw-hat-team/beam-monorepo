defmodule Trogon.Outbox.TestSupport.ObanJobs do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Trogon.Outbox.TestRepo

  @poll_interval_ms 20

  @spec truncate!() :: :ok
  def truncate! do
    SQL.query!(TestRepo, "TRUNCATE TABLE oban_jobs, oban_peers RESTART IDENTITY")
    :ok
  end

  @spec fetch(pos_integer()) :: Oban.Job.t() | nil
  def fetch(id), do: TestRepo.get(Oban.Job, id)

  @spec state!(pos_integer()) :: String.t()
  def state!(id), do: TestRepo.get!(Oban.Job, id).state

  @spec count!() :: non_neg_integer()
  def count!, do: TestRepo.aggregate(Oban.Job, :count)

  @spec backdate!(pos_integer(), atom(), pos_integer()) :: :ok
  def backdate!(id, column, seconds) when column in [:inserted_at, :scheduled_at, :attempted_at, :discarded_at] do
    SQL.query!(
      TestRepo,
      "UPDATE oban_jobs SET #{column} = #{column} - make_interval(secs => $2) WHERE id = $1",
      [id, seconds]
    )

    :ok
  end

  @doc """
  Polls `fun` until it returns a truthy value or `timeout_ms` elapses, returning
  the last value it produced.
  """
  @spec eventually((-> any()), pos_integer()) :: any()
  def eventually(fun, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(fun, deadline)
  end

  defp poll(fun, deadline) do
    result = fun.()

    if result || System.monotonic_time(:millisecond) >= deadline do
      result
    else
      Process.sleep(@poll_interval_ms)
      poll(fun, deadline)
    end
  end
end
