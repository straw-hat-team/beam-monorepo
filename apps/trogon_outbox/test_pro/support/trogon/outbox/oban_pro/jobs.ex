defmodule Trogon.Outbox.ObanPro.Jobs do
  @moduledoc false

  alias Trogon.Outbox.ObanPro.TestRepo

  @spec truncate!() :: :ok
  def truncate! do
    TestRepo.query!("TRUNCATE TABLE public.oban_jobs, public.oban_producers, public.oban_peers, public.oban_workflows")

    TestRepo.query!(
      "TRUNCATE TABLE unindexed.oban_jobs, unindexed.oban_producers, unindexed.oban_peers, unindexed.oban_workflows"
    )

    :ok
  end

  @spec state(pos_integer(), String.t()) :: String.t() | nil
  def state(id, prefix \\ "public") do
    case TestRepo.query!("SELECT state FROM #{prefix}.oban_jobs WHERE id = $1", [id]).rows do
      [[state]] -> state
      [] -> nil
    end
  end

  @spec count_by_key(term(), String.t()) :: non_neg_integer()
  def count_by_key(key, prefix \\ "public") do
    %Postgrex.Result{rows: [[count]]} =
      TestRepo.query!("SELECT count(*) FROM #{prefix}.oban_jobs WHERE args ->> 'key' = $1", [to_string(key)])

    count
  end

  @spec delete!(pos_integer()) :: :ok
  def delete!(id) do
    TestRepo.query!("DELETE FROM public.oban_jobs WHERE id = $1", [id])
    :ok
  end

  @spec delete_producers!(atom()) :: :ok
  def delete_producers!(name) do
    TestRepo.query!("DELETE FROM public.oban_producers WHERE name = $1", [to_string(name)])
    :ok
  end

  @doc "Polls `fun` until it returns a truthy value, raising once `timeout_ms` elapses."
  @spec wait_until((-> any()), pos_integer(), pos_integer()) :: any()
  def wait_until(fun, timeout_ms \\ 5_000, interval_ms \\ 50) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll(fun, deadline, interval_ms)
  end

  defp poll(fun, deadline, interval_ms) do
    case fun.() do
      result when result not in [false, nil] ->
        result

      _falsy ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise ExUnit.AssertionError, message: "wait_until/3 timed out"
        else
          Process.sleep(interval_ms)
          poll(fun, deadline, interval_ms)
        end
    end
  end
end
