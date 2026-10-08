defmodule Trogon.Outbox.TestSupport.FlakyPublisher do
  @moduledoc """
  An in-memory publisher that randomly fails or raises before eventually succeeding, to exercise
  a relay's retry and backoff under chaos. Modeled after `TestPublisher`, with failure injection
  added.

  Random decisions are seeded once per calling process from `:seed` in `opts`, so a relay process
  always makes the same sequence of decisions for a given seed. A relay that is killed and
  restarted runs in a new process, which reseeds from the same value and starts that sequence
  over.

  ## Options

    * `:seed` - the integer to seed this process's random decisions from. Required.
    * `:counter` - an `Agent` holding attempt counts per batch, shared across every relay process
      using this publisher so a batch keeps failing across a relay restart until it has failed
      `:max_failures` times in total. Required.
    * `:on_publish` - called with the batch once it is actually delivered. Required.
    * `:failure_rate` - the chance, from 0.0 to 1.0, that a batch not yet past `:max_failures`
      attempts fails, 0.3 by default.
    * `:max_failures` - the number of failed attempts a given batch gets before it always
      succeeds, 3 by default.
  """

  @behaviour Trogon.Outbox.Publisher

  alias Trogon.Outbox.Batch

  @impl Trogon.Outbox.Publisher
  def publish(%Batch{} = batch, opts) do
    ensure_seeded(Keyword.fetch!(opts, :seed))

    key = batch_key(batch)
    attempt = next_attempt(Keyword.fetch!(opts, :counter), key)
    max_failures = Keyword.get(opts, :max_failures, 3)
    failure_rate = Keyword.get(opts, :failure_rate, 0.3)

    if attempt < max_failures and :rand.uniform() < failure_rate do
      inject_failure(key, attempt)
    else
      Keyword.fetch!(opts, :on_publish).(batch)
      :ok
    end
  end

  defp next_attempt(counter, key) do
    Agent.get_and_update(counter, fn counts ->
      attempt = Map.get(counts, key, 0)
      {attempt, Map.put(counts, key, attempt + 1)}
    end)
  end

  defp inject_failure(key, attempt) do
    if :rand.uniform() < 0.5 do
      raise "FlakyPublisher induced failure for #{inspect(key)} on attempt #{attempt}"
    else
      {:error, {:flaky_publisher_induced_failure, key, attempt}}
    end
  end

  defp batch_key(%Batch{partition: partition} = batch) do
    cursor = Batch.cursor(batch)
    {partition.value, cursor.xid, cursor.id}
  end

  defp ensure_seeded(seed) do
    key = {__MODULE__, :seeded}

    unless Process.get(key) do
      :rand.seed(:exsss, {seed, seed, seed})
      Process.put(key, true)
    end
  end
end
